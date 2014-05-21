#!/bin/bash
#
# setup_datanode.sh sets up this node's (localhost's) environment for hadoop
# workloads. Everything needed other than volume-specific tasks is done here.
# It is assumed that localhost has already been validated (eg. check_node.sh
# has been run) prior to setting up the node.
# Syntax:
#  --blkdev: block dev path(s) (optional), skip xfs and blk-mnts if missing
#  --brkmnt: brick mnt path(s) (optional), skip xfs and blk-mnts if missing
#  --hadoop-mgmt-node: hostname or ip of the hadoop mgmt server (expected to
#       be outside of the storage pool) (required)
#  -q, if specified, means only set the exit code, do not output anything
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
#   QUIET
function parse_cmd() {

  local opts='q'
  local long_opts='blkdev:,brkmnt:,hadoop-mgmt-node:'
  local errcnt=0

  eval set -- "$(getopt -o $opts --long $long_opts -- $@)"

  while true; do
      case "$1" in
        -q)
          QUIET=1; shift; continue # true
        ;;
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
  [[ -z "$MGMT_NODE" ]] && {
    echo "Syntax error: hadoop-mgmt-node is required";
    ((errcnt++)); }

  # convert list of 1 or more blkdevs and brkmnts to arrays
  BLKDEV=(${BLKDEV//,/ })
  BRICKMNT=(${BRICKMNT//,/ })

  (( errcnt > 0 )) && return 1
  return 0
}

# mount_blkdev: create the brick-mnt dir(s) if needed, append the xfs brick
# mount to /etc/fstab, and then mount it. Returns 1 on errors.
function mount_blkdev() {

  local err; local errcnt=0; local out
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
 	out="$(mount $brkmnt 2>&1)" # via fstab entry
 	err=$?
 	if (( err != 0 )) ; then
	  echo "ERROR $err: mount $blkdev as $brkmnt: $out"
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

  local out; local err; local errcnt=0
  local AMBARI_INI='/etc/ambari-agent/conf/ambari-agent.ini'
  local AMBARI_AGENT_PID='/var/run/ambari-agent/ambari-agent.pid'

  get_ambari_repo

  # stop agent if running
  if [[ -f $AMBARI_AGENT_PID ]] ; then
    out="$(ambari-agent stop 2>&1)"
    err=$?
    (( ! QUIET )) && echo "ambari-agent stop: $out"
    if (( err != 0 )) ; then
      echo "WARN $err: couldn't stop ambari agent: $out"
    fi
  fi

  # install agent
  out="$(yum -y install ambari-agent 2>&1)"
  err=$?
  (( ! QUIET )) && echo "ambari-agent install: $out"
  if (( err != 0 && err != 1 )) ; then # 1--> nothing-to-do
    echo "ERROR $err: ambari-agent install: $out"
    return 1
  fi

  if [[ ! -f $AMBARI_INI ]] ; then
    echo "ERROR: $AMBARI_INI file missing"
    return 1
  fi

  # modify the agent's .ini file to contain the mgmt node hostname
  sed -i -e "s/hostname=localhost/hostname=${MGMT_NODE}/" $AMBARI_INI

  # start the agent now
  out="$(ambari-agent start 2>&1)"
  err=$?
  (( ! QUIET )) && echo "ambari-agent start: $out"
  if (( err != 0 )) ; then
    echo "ERROR $err: ambari-agent start: $out"
    return 1
  fi

  # persist the agent after reboot
  out="$(chkconfig ambari-agent on 2>&1)"
  err=$?
  (( ! QUIET )) && echo "ambari-agent chkconfig on: $out"
  if (( err != 0 )) ; then
    echo "ERROR $err: ambari-agent chkconfig on: $out"
    return 1
  fi

  return 0
}

# setup_iptables: open ports for the known gluster, ambari and hadoop services.
function setup_iptables() {

  local err; local errcnt=0; local out
  local port; local proto
  local iptables_conf='/etc/sysconfig/iptables'

  for port in $($PREFIX/gen_ports.sh); do
      proto=${port#*:}
      port=${port%:*}; port=${port/-/:} # use iptables range syntax
      # open up this port or port range for the target protocol ONLY if not
      # already open
      if ! grep -qs -E "^-A .* -p $proto .* $port .*ACCEPT" $iptables_conf; then
	out="$(iptables -A INPUT -m state --state NEW -m $proto \
		-p $proto --dport $port -j ACCEPT)"
	err=$?
	(( ! QUIET )) && echo "iptables: $out"
	if (( err != 0 )) ; then
	  echo "ERROR $err: iptables port $port: $out"
 	  ((errcnt++))
	fi
      fi
  done
  
  # save iptables
  out="$(service iptables save)"
  err=$?
  (( ! QUIET )) && echo "iptables save: $out"
  if (( err != 0 )) ; then
    echo "ERROR $err: iptables save: $out"
    ((errcnt++))
  fi

  # restart iptables
  out="$(service iptables restart)"
  err=$?
  (( ! QUIET )) && echo "iptables restart: $out"
  if (( err != 0 )) ; then
    echo "ERROR $err: iptables restart: $out"
    ((errcnt++))
  fi

  (( errcnt > 0 )) && return 1
  return 0
}

# setup_selinux: if selinux is enabled then set it to permissive. This seems
# to be a requirement for HDP.
function setup_selinux() {

  local out; local err
  local conf='/etc/sysconfig/selinux' # symlink to /etc/selinux/config
  local selinux_key='SELINUX='
  local permissive='permissive'

  # set selinux to permissive (audit errors reported but not enforced)
  out="$(setenforce $permissive 2>&1)"
  (( ! QUIET )) && echo "$out"

  # keep selinux permissive on reboots
  if [[ ! -f $conf ]] ; then
    (( ! QUIET )) && echo "WARN: SELinux config file $conf missing"
    return # nothing more to do...
  fi

  # config SELINUX=permissive which takes effect the next reboot
  out="$(sed -i -e "/^$selinux_key/c\\$selinux_key$permissive" $conf)"
  err=$?
  if (( err != 0 )) ; then
    (( ! QUIET )) && echo "ERROR $err: setting selinux permissive in $CONF"
    return 1
  fi
}

# setup_xfs: mkfs.xfs on the block device. Returns 1 on error.
function setup_xfs() {

  local blkdev; local err; local errcnt=0; local out
  local isize=512

  [[ -z "$BLKDEV" ]] && return 0 # nothing to do...

  for blkdev in ${BLKDEV[@]}; do
      if ! xfs_info $blkdev >& /dev/null ; then
	out="$(mkfs -t xfs -i size=$isize -f $blkdev 2>&1)"
	err=$?
	(( ! QUIET )) && echo "mkfs.xfs on $blkdev: $out"
	if (( err != 0 )) ; then
	  echo "ERROR $err: mkfs.xfs on $blkdev: $out"
	  ((errcnt++))
	fi
      fi
  done

  (( errcnt > 0 )) && return 1
  return 0
}


## main ##

QUIET=0 # false (meaning not quiet)
errcnt=0; q=''

parse_cmd $@ || exit -1
(( QUIET )) && q='-q'

setup_xfs          || ((errcnt++))
mount_blkdev       || ((errcnt++))
setup_selinux      || ((errcnt++))
setup_iptables     || ((errcnt++))
setup_ambari_agent || ((errcnt++))

$PREFIX/add_groups.sh $q              || ((errcnt++))
$PREFIX/add_users.sh $q               || ((errcnt++))
if [[ -n "$BRICKMNT" ]] ; then # need brick mount prefix
  $PREFIX/add_dirs.sh -l $q $BRICKMNT || ((errcnt++)) # just local dirs
fi

(( errcnt > 0 )) && exit 1
(( ! QUIET )) && echo "Node $(hostname) successfully setup"
exit 0
