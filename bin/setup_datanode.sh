#!/bin/bash
#
# setup_datanode.sh sets up this node's (localhost's) environment for hadoop
# workloads. Everything needed other than volume-specific tasks is done here.
# Syntax:
#  $1=block device path(s)
#  $2=brick mount path(s)
#  $3=hadoop/ambari management node
#  -q, if specified, means only set the exit code, do not output anything

errcnt=0; q=''

PREFIX="$(dirname $(readlink -f $0))"
[[ ${PREFIX##*/} != 'bin' ]] && PREFIX+='/bin'

# get_ambari_repo: wget the ambari repo file in the correct location.
function get_ambari_repo(){
 
  local REPO_DIR='/etc/yum.repos.d'
  local REPO_URL='http://public-repo-1.hortonworks.com/ambari/centos6/1.x/updates/1.4.4.23/ambari.repo'
  local out; local err; local errcnt=0

  [[ -d $REPO_DIR ]] || mkdir -p $REPO_DIR
  cd $REPO_DIR

  out="$(wget $REPO_URL 2>&1)"
  err=$?
  [[ -z "$QUIET" ]] && echo "wget ambari repo: $out"
  if (( err != 0 )) ; then
    [[ -z "$QUIET" ]] && echo "ERROR $err: ambari repo wget"
    ((errcnt++))
  fi

  cd - >/dev/null

  (( errcnt > 0 )) && return 1
  return 0
}

# setup_ambari_agent: yum install the ambari agent rpm, modify the .ini file
# to point to the ambari server, start the agent, and set up agent to start
# automatically after a reboot.
function setup_ambari_agent() {

  local out; local err; local errcnt=0
  local AMBARI_INI='/etc/ambari-agent/conf/ambari-agent.ini'
  local AMBARI_AGENT_PID='/var/run/ambari-agent/ambari-agent.pid'

  get_ambari_repo

  # stop agent if running
  if [[ -f $AMBARI_AGENT_PID ]] ; then
    out="$(ambari-agent stop 2>&1)"
    err=$?
    [[ -z "$QUIET" ]] && echo echo "ambari-agent stop: $out"
    if (( err != 0 )) ; then
      [[ -z "$QUIET" ]] && echo echo "WARN $err: couldn't stop ambari agent"
    fi
  fi

  # install agent
  out="$(yum -y install ambari-agent 2>&1)"
  err=$?
  [[ -z "$QUIET" ]] && echo echo "ambari-agent install: $out"
  if (( err != 0 && err != 1 )) ; then # 1--> nothing-to-do
    [[ -z "$QUIET" ]] && echo echo "ERROR $err: ambari-agent install"
    return 1
  fi

  # modify the agent's .ini file to contain the mgmt node hostname
  sed -i -e "s/'localhost'/${MGMT_NODE}/" $AMBARI_INI >& /dev/null

  # start the agent now
  out="$(ambari-agent start 2>&1)"
  err=$?
  [[ -z "$QUIET" ]] && echo "ambari-agent start: $out"
  if (( err != 0 )) ; then
    [[ -z "$QUIET" ]] && echo "ERROR $err: ambari-agent start"
    return 1
  fi

  # persist the agent after reboot
  out="$(chkconfig ambari-agent on 2>&1)"
  [[ -z "$QUIET" ]] && echo "ambari-agent chkconfig on: $out"
  return 0
}

# setup_iptables: open ports for the known gluster, ambari and hadoop services.
function setup_iptables() {

  local err; local errcnt=0; local out
  local port; local proto

  for port in $($PREFIX/gen_ports.sh); do
      proto=${port#*:}
      port=${port%:*}
      [[ "$port" =~ [0-9]\- ]] && port=${port/-/:} # use iptables range syntax
      # open this port or range of port numbers for the target protocol
      out="$(iptables -A RHS-Firewall-1-INPUT -m state --state NEW -m $proto \
	-p $proto --dport $port -j ACCEPT)"
      err=$?
      if (( err != 0 )) ; then
	[[ -z "$QUIET" ]] && echo "ERROR $err: iptables port $port: $out"
 	((errcnt++))
      fi
  done
  
  # save and restart iptables
  service iptables save
  service iptables restart

  (( errcnt > 0 )) && return 1
  return 0
}

# mount_blkdev: append the xfs brick mount(s) to /etc/fstab and then mount 
# it/them.
function mount_blkdevs() {

  local i; local err; local out
  local brkmnt; local blkdev
  local blkdevs=($BLKDEVS); local brickmnts=($BRICKMNTS) # convert to arrays
  local brick_mnt_opts="noatime,inode64"

  for (( i=0; i<${#blkdevs}; i++ )) ; do
      blkdev="${blkdevs[$i]}"; brkmnt="${brickmnts[$i]}"
      if ! grep -qsw $brkmnt /etc/fstab ; then
	echo "$blkdev $brkmnt xfs $brick_mnt_opts 0 0" >>/etc/fstab
      fi
      out="$(mount $brkmnt)" # via fstab entry
      err=$?
  done
}


## main ##

# parse cmd opts
while getopts ':q' opt; do
    case "$opt" in
      q)
        QUIET=true # else, undefined
        shift
        ;;
      \?) # invalid option
        shift # silently ignore opt
        ;;
    esac
done

BLKDEVS="$1"   # required, can be a list or a single value
BRICKMNTS="$2" # required, can be a list or a single value
MGMT_NODE="$3" # required
[[ -n "$QUIET" ]] && q='-q'

setup_xfs          || ((errcnt++))
setup_ntp          || ((errcnt++))
setup_selinux      || ((errcnt++))
setup_iptables     || ((errcnt++))
setup_ambari_agent || ((errcnt++))
mount_blkdevs      || ((errcnt++))

$PREFIX/add_users.sh $q  || ((errcnt++))
$PREFIX/add_groups.sh $q || ((errcnt++))
$PREFIX/add_dirs.sh $q   || ((errcnt++))

(( errcnt > 0 )) && exit 1
[[ -z "$QUIET" ]] && echo "${#VOL_SETTINGS[@]} volume settings successfully set"
exit 0
