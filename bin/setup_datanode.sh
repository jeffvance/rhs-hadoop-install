#!/bin/bash
#
# setup_datanode.sh sets up this node's (localhost's) environment for hadoop
# workloads. Everything needed other than volume-specific tasks is done here.
# It is assumed that localhost has already been validated (eg. check_node.sh
# has been run) prior to setting up the node.
# Syntax:
#  --blkdev:  (optional) block dev path(s), skip xfs and blk-mnts if missing.
#  --brkmnt:  (optional) brick mnt path(s), skip xfs and blk-mnts if missing.
#  --profile: (optional) rhs/kernel profile, won't set a profile if missing.
#  --ambari-repo:  (optional) ambari repo file url.
#  --force-ambari: (optional) if passed then update the agent even if running.
#  --hadoop-mgmt-node: (optional) hostname or ip of the hadoop mgmt server 
#       (expected to be outside of the storage pool). Default=localhost.
#
# Note: the blkdev and brkmnt values can be a list of 1 or more paths separated
#   by a comma (no spaces).

PREFIX="$(dirname $(readlink -f $0))"

## functions ##
source $PREFIX/functions

# parse_cmd: use get_opt to parse the command line. Returns 1 on errors.
# Sets globals:
#   AMBARI_REPO
#   BLKDEV()
#   BRICKMNT()
#   FORCE_AMBARI
#   MGMT_NODE
#   PROFILE
function parse_cmd() {

  local long_opts='blkdev::,brkmnt::,profile::,hadoop-mgmt-node:,ambari-repo::,force-ambari'

  eval set -- "$(getopt -o'-' --long $long_opts -- $@)"

  while true; do
      case "$1" in
        --blkdev) # optional
	  shift 2
	  [[ "${1:0:2}" == '--' ]] && continue # missing option value
          BLKDEV="$1"; shift; continue
        ;;
        --brkmnt) # optional
	  shift 2
	  [[ "${1:0:2}" == '--' ]] && continue # missing option value
          BRICKMNT="$1"; shift; continue
        ;;
        --profile) # optional
	  shift 2
	  [[ "${1:0:2}" == '--' ]] && continue # missing option value
          PROFILE="$1"; shift; continue
        ;;
        --ambari-repo) # optional
	  shift 2
	  [[ "${1:0:2}" == '--' ]] && continue # missing option value
          AMBARI_REPO="$1"; shift; continue
        ;;
        --force-ambari) # optional
          FORCE_AMBARI=1; shift; continue
        ;;
        --hadoop-mgmt-node)
          MGMT_NODE="$2"; shift 2; continue
        ;;
        --)
          shift; break
        ;;
      esac
  done

  # fill in defaults
  [[ -z "$MGMT_NODE" ]]    && MGMT_NODE="$HOSTNAME"
  [[ -z "$FORCE_AMBARI" ]] && FORCE_AMBARI=0 # false

  # convert list of 1 or more blkdevs and brkmnts to arrays
  BLKDEV=(${BLKDEV//,/ })
  BRICKMNT=(${BRICKMNT//,/ })

  return 0
}

# mount_blkdev: on this storage node, create the brick-mnt dir(s) if needed,
# append the xfs brick mount to /etc/fstab, and then mount it. Returns 1 on
# errors.
function mount_blkdev() {

  local err; local errcnt=0
  local blkdev; local brkmnt; local i=0
  local mntopts="noatime,inode64"

  [[ -z "$BLKDEV" || -z "$BRICKMNT" ]] && return 0 # need both to mount bricks

  (( STORAGE_NODE )) || {
    echo "$HOSTNAME is not a RHS storage node, skipping block dev mount";
    return 0; } # nothing to do...

  for brkmnt in ${BRICKMNT[@]}; do
      blkdev=${BLKDEV[$i]}
      [[ ! -e $brkmnt ]] && mkdir -p $brkmnt

      if ! grep -qsw $brkmnt /etc/fstab ; then
 	echo "$blkdev $brkmnt xfs $mntopts 0 0" >>/etc/fstab
      fi

      if ! grep -qsw $brkmnt /proc/mounts ; then
 	mount $brkmnt 2>&1 # via fstab entry
 	err=$?
 	if (( err != 0 )) ; then
	  echo "ERROR $err: mount $blkdev as $brkmnt"
	  ((errcnt++))
	fi
      fi
      ((i++))
  done

  (( errcnt > 0 )) && return 1
  return 0
}

# setup_ambari_agent: unless the agent is already running, yum install the
# ambari agent rpm, modify the .ini file to point to the ambari server, start
# the agent, and set up agent to start automatically after a reboot. 
# Returns 1 on errors.
# NOTE: if FORCE_AMBARI is set then even if the agent is running it will be re-
#   yum installed and started.
function setup_ambari_agent() {

  local err; local errcnt=0
  local AMBARI_INI='/etc/ambari-agent/conf/ambari-agent.ini'
  local AMBARI_AGENT_PID='/var/run/ambari-agent/ambari-agent.pid'

  echo "setting up the ambari agent..."

  # detect if agent is running
  if [[ -f $AMBARI_AGENT_PID ]] && \
     which ambari-agent >& /dev/null && \
     ambari-agent status >& /dev/null ; then # agent is definitely running
    (( ! FORCE_AMBARI )) && {
      echo "ambari-agent is running, install skipped";
      return 0; } # done
    echo "stopping ambari-agent since running in \"FORCE\" mode"
    ambari-agent stop 2>&1
    err=$?
    (( err != 0 )) && echo "WARN $err: couldn't stop ambari agent"
  fi

  get_ambari_repo $AMBARI_REPO
  err=$?
  (( err != 0 )) && {
    echo "ERROR $err: can't wget ambari repo $AMBARI_REPO";
    return 1; }

  # install agent
  yum -y install ambari-agent 2>&1
  err=$?
  if (( err != 0 )) ; then
    echo "ERROR $err: ambari-agent install"
    return 1
  fi

  if [[ ! -f $AMBARI_INI ]] ; then
    echo "ERROR: $AMBARI_INI file missing"
    return 1
  fi

  # modify the agent's .ini file to contain the mgmt node hostname
  sed -i -e "s/hostname=localhost/hostname=${MGMT_NODE}/" $AMBARI_INI

  # start the agent now
  ambari-agent start 2>&1
  err=$?
  if (( err != 0 )) ; then
    echo "ERROR $err: ambari-agent start"
    return 1
  fi

  # persist the agent after reboot
  chkconfig ambari-agent on 2>&1
  err=$?
  if (( err != 0 )) ; then
    echo "ERROR $err: ambari-agent chkconfig on"
    return 1
  fi

  echo "done setting up the ambari agent"
  return 0
}

# setup_ntp: validate the ntp conf file, start ntpd, synch time. Returns 1 on
# errors.
function setup_ntp() {

  local errcnt=0; local warncnt=0; local cnt=0; local err

  # validate ntp config file
  if ! validate_ntp_conf ; then  # we're hosed: can't sync time nor start ntpd
    echo "ERROR: $HOSTNAME cannot proceed with ntp validation due to config file error"
    return 1
  fi

  # stop ntpd so that ntpd -qg can potentially do a large time change
  while ps -C ntpd >& /dev/null ; do
    service ntpd stop >& /dev/null
    (( cnt > 2 )) && break
    ((cnt++))
  done
  (( cnt > 2 )) && {
    echo "ERROR: cannot stop ntpd so that time can be synched";
    ((errcnt++)); }

  # set time to ntp clock time now (ntpdate is being deprecated)
  # note: ntpd can't be running...
  ntpd -qg 2>&1
  err=$?
  (( err != 0 )) && {
    echo "WARN $err: ntpd -qg (aka ntpdate)";
    ((warncnt++)); }

  # start ntpd
  service ntpd start 2>&1
  err=$?
  (( err != 0 )) && {
    echo "ERROR $err: ntpd start"
    ((errcnt++)); }

  (( errcnt > 0 )) && return 1
  echo "ntp setup with $warncnt warnings"
  return 0
}

# setup_xfs: on this storage node, mkfs.xfs on the block device. Returns 1 on
# errors.
function setup_xfs() {

  local blkdev; local err; local errcnt=0
  local isize=512

  [[ -z "$BLKDEV" ]] && return 0 # nothing to do...
  (( STORAGE_NODE )) || return 0 # nothing to do...

  for blkdev in ${BLKDEV[@]}; do
      if ! xfs_info $blkdev >& /dev/null ; then
	mkfs -t xfs -i size=$isize -f $blkdev 2>&1
	err=$?
	if (( err != 0 )) ; then
	  echo "ERROR $err: mkfs.xfs on $blkdev"
	  ((errcnt++))
	fi
      fi
  done

  (( errcnt > 0 )) && return 1
  return 0
}

# add_local_dirs: add the local directories under the first brick mount point.
# So, even if multiple brick mounts are defined for this node, we only create
# one set of local dirs (eg. mapredlocal). Returns add_dir's rtn-code
function add_local_dirs() {

  [[ -z "$BRICKMNT" ]] && return 0 # nothing to do

  $PREFIX/add_dirs.sh ${BRICKMNT[0]} $($PREFIX/gen_dirs.sh -l)
}

# setup_profile: apply the PROFILE tune-adm profile to this storage node.
# Returns 1 on errors.
function setup_profile() {

  local tuned_path="/etc/tune-profiles/$PROFILE"
  local err

  [[ -z "$PROFILE" ]] && return 0 # leave default profile set

  (( STORAGE_NODE )) || {
    echo "$HOSTNAME is not a RHS storage node, skipping tuned-adm step";
    return 0; } # nothing to do...

  [[ -d $tuned_path ]] || {
    echo "ERROR: $tuned_path directory is missing, can't set $PROFILE profile";
    return 1; }

  tuned-adm profile $PROFILE 2>&1
  err=$?
  (( err != 0 )) && {
    echo "ERROR $err: tuned-adm profile";
    return 1; }

  return 0
}


## main ##

errcnt=0
STORAGE_NODE=$([[ -f /etc/redhat-storage-release ]] && echo 1 || echo 0)

parse_cmd $@ || exit -1

setup_xfs          || ((errcnt++))
mount_blkdev       || ((errcnt++))
setup_selinux      || ((errcnt++))
setup_ntp          || ((errcnt++))
setup_ambari_agent || ((errcnt++))
add_local_dirs     || ((errcnt++))
setup_firewall     || ((errcnt++))
setup_profile      || ((errcnt++))

(( errcnt > 0 )) && exit 1
echo "Node $HOSTNAME successfully setup"
exit 0
