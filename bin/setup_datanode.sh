#!/bin/bash
#
# setup_datanode.sh sets up this node's (localhost's) environment for hadoop
# workloads. Everything needed other than volume-specific tasks is done here.
# It is assumed that localhost has already been validated (eg. check_node.sh
# has been run) prior to setting up the node.
# Syntax:
#  --blkdev: block dev path(s) (optional), skip xfs and blk-mnts if missing.
#  --brkmnt: brick mnt path(s) (optional), skip xfs and blk-mnts if missing.
#  --hadoop-mgmt-node: hostname or ip of the hadoop mgmt server (expected to
#       be outside of the storage pool) (optional, default=localhost).
#
# Note: the blkdev and brkmnt values can be a list of 1 or more paths separated
#   by a comma (no spaces).

PREFIX="$(dirname $(readlink -f $0))"

## functions ##
source $PREFIX/functions

# parse_cmd: use get_opt to parse the command line. Returns 1 on errors.
# Sets globals:
#   BLKDEV()
#   BRICKMNT()
#   MGMT_NODE
function parse_cmd() {

  local long_opts='blkdev:,brkmnt:,hadoop-mgmt-node:'

  eval set -- "$(getopt -o '' --long $long_opts -- $@)"

  while true; do
      case "$1" in
        --blkdev) # optional
	  shift
	  [[ "${1:0:2}" == '--' ]] && continue # missing option value
          BLKDEV="$1"; shift; continue
        ;;
        --brkmnt) # optional
	  shift
	  [[ "${1:0:2}" == '--' ]] && continue # missing option value
          BRICKMNT="$1"; shift; continue
        ;;
        --hadoop-mgmt-node)
          MGMT_NODE="$2"; shift 2; continue
        ;;
        --)
          shift; break
        ;;
      esac
  done

  # check required args
  [[ -z "$MGMT_NODE" ]] && MGMT_NODE="$HOSTNAME"

  # convert list of 1 or more blkdevs and brkmnts to arrays
  BLKDEV=(${BLKDEV//,/ })
  BRICKMNT=(${BRICKMNT//,/ })

  return 0
}

# mount_blkdev: create the brick-mnt dir(s) if needed, append the xfs brick
# mount to /etc/fstab, and then mount it. Returns 1 on errors.
function mount_blkdev() {

  local err; local errcnt=0
  local blkdev; local brkmnt; local i=0
  local mntopts="noatime,inode64"

  [[ -z "$BLKDEV" || -z "$BRICKMNT" ]] && return 0 # need both to mount brickt

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

# setup_ambari_agent: yum install the ambari agent rpm, modify the .ini file
# to point to the ambari server, start the agent, and set up agent to start
# automatically after a reboot. Returns 1 on errors.
function setup_ambari_agent() {

  local err; local errcnt=0
  local AMBARI_INI='/etc/ambari-agent/conf/ambari-agent.ini'
  local AMBARI_AGENT_PID='/var/run/ambari-agent/ambari-agent.pid'

  get_ambari_repo

  # stop agent if running
  if [[ -f $AMBARI_AGENT_PID ]] ; then
    ambari-agent stop 2>&1
    err=$?
    if (( err != 0 )) ; then
      echo "WARN $err: couldn't stop ambari agent"
    fi
  fi

  # install agent
  yum -y install ambari-agent 2>&1
  err=$?
  if (( err != 0 && err != 1 )) ; then # 1--> nothing-to-do
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

  return 0
}

# setup_ntp: validate the ntp conf file, start ntpd, synch time. Returns 1 on
# errors.
function setup_ntp() {

  local errcnt=0; local warncnt=0; local cnt=0; local err

  # validate ntp config file
  if ! validate_ntp_conf ; then  # we're hosed: can't sync time nor start ntpd
    echo "ERROR: cannot proceed with ntp validation due to config file error"
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

# setup_selinux: if selinux is enabled then set it to permissive. This seems
# to be a requirement for HDP. Returns 1 on errors.
function setup_selinux() {

  local err
  local conf='/etc/sysconfig/selinux' # symlink to /etc/selinux/config
  local selinux_key='SELINUX='
  local permissive='permissive'

  # set selinux to permissive (audit errors reported but not enforced)
  setenforce $permissive 2>&1

  # keep selinux permissive on reboots
  if [[ ! -f $conf ]] ; then
    echo "WARN: SELinux config file $conf missing"
    return # nothing more to do...
  fi

  # config SELINUX=permissive which takes effect the next reboot
  sed -i -e "/^$selinux_key/c\\$selinux_key$permissive" $conf
  err=$?
  if (( err != 0 )) ; then
    echo "ERROR $err: trying to set selinux to permissive in $conf"
    return 1
  fi
}

# setup_xfs: mkfs.xfs on the block device. Returns 1 on error.
function setup_xfs() {

  local blkdev; local err; local errcnt=0
  local isize=512

  [[ -z "$BLKDEV" ]] && return 0 # nothing to do...

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

# add_local_dirs: add the local directories for each brick mount if the brick
# mount is defined.
function add_local_dirs() {

  local brkmnt; local errcnt=0

  [[ -z "$BRICKMNT" ]] && return 0 # nothing to do

  for brkmnt in ${BRICKMNT[*]}; do
      $PREFIX/add_dirs.sh -l $brkmnt || ((errcnt++))
  done

  (( errcnt > 0 )) && return 1
  return 0
}


## main ##

errcnt=0; q=''

parse_cmd $@ || exit -1

setup_xfs          || ((errcnt++))
mount_blkdev       || ((errcnt++))
setup_selinux      || ((errcnt++))
setup_ntp          || ((errcnt++))
setup_ambari_agent || ((errcnt++))

$PREFIX/setup_firewall.sh || ((errcnt++))
$PREFIX/add_groups.sh     || ((errcnt++))
$PREFIX/add_users.sh      || ((errcnt++))
add_local_dirs            || ((errcnt++))

(( errcnt > 0 )) && exit 1
echo "Node $(hostname) successfully setup"
exit 0
