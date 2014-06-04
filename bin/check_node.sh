#!/bin/bash
#
# check_node.sh verifies that the node running this script is setup correctly
# for hadoop workloads. This includes everything other than volume-specific
# checks. So, we check: ntp config, required gluster and ambari ports being
# open, ambari agent running, selinux not enabled, hadoop users and local hadoop
# directories exist.
# Syntax:
#  $1= xfs brick mount directory path including the volume name

PREFIX="$(dirname $(readlink -f $0))"

## functions ##

source $PREFIX/functions

# check_ambari_agent: see if the ambari agent is running on this node.
function check_ambari_agent() {

  local ambari_agent_pid='/var/run/ambari-agent/ambari-agent.pid'
  local errcnt=0; local warncnt=0; local pid

  if [[ ! -f $ambari_agent_pid ]] ; then
    echo "ERROR: $ambari_agent_pid file missing on $NODE"
    return 1
  fi

  # extract ambari-agent pid
  pid=$(cat $ambari_agent_pid)
  if ! ps -p $pid >& /dev/null ; then
    "ERROR: ambari-agent process $pid is not running"
    ((errcnt++))
  fi

  (( errcnt > 0 )) && return 1
  echo "ambari-agent is running on $NODE with $warncnt warnings"
  return 0
}

# check_brick_mount: use xfs_info to verify the brick mnt is xfs (if not error)
# and the isize = 512 (if not warning).
function check_brick_mount() {

  local out; local isize=512; local errcnt=0; local warncnt=0

  # errors have already been reported by check_xfs() for missing brick mtn dirs
  [[ ! -d $BRICKMNT ]] && return

  xfs_info $BRICKMNT 2>&1
  err=$?
  if (( err != 0 )) ; then
    echo "ERROR $err: xfs_info on $BRICKMNT"
    ((errcnt++))
  else
    out="$(cut -d' ' -f2 <<<$out | cut -d'=' -f2)" # isize value
    if (( out != isize )) ; then
      echo "WARN: xfs size on $BRICKMNT expected to be $isize; found $out"
      ((warncnt++))
    fi
  fi

  (( errcnt > 0 )) && return 1
  echo "xfs brick mount setup correctly on $NODE with $warncnt warnings"
  return 0
}

# check_dirs: check that the required hadoop local directories are present on
# this node. Also check that the perms and owner are set correctly.
function check_dirs() {

  local dir; local perm; local owner; local tuple
  local out; local errcnt=0; local warncnt=0

  for tuple in $($PREFIX/gen_dirs.sh -l); do # only local dirs
      dir="$BRICKMNT/${tuple%%:*}"
      perm=${tuple%:*}; perm=${perm#*:}
      owner=${tuple##*:}

      if [[ ! -d $dir ]] ; then
	echo "ERROR: $dir is missing on $NODE"
	((errcnt++))
	continue # next dir
      fi

      # check dir's perms and owner
      out="$(stat -c %a $dir)"
      [[ ${#out} == 3 ]] && out="0$out"; # leading 0
      if [[ $out != $perm ]] ; then
	echo "WARN: $dir perms are $out, expected to be: $perm"
	((warncnt++))
      fi
      out="$(stat -c %U $dir)"
      if [[ $out != $owner ]] ; then
	echo "WARN: $dir owner is $out, expected to be: $owner"
	((warncnt++))
      fi
  done

  (( errcnt > 0 )) && return 1
  echo "all required dirs present on $NODE with $warncnt warnings"
  return 0
}

# check_open_ports: verify that the ports needed by gluster and ambari are all
# open, both "live" (iptables) and persisted (iptables conf file).
function check_open_ports() {

  # return 0 if iptables is not even running
  if ! service iptables status >& /dev/null ; then
    echo "iptables not running on $HOSTNAME"
    return 0
  fi

  # return 0 if iptables is running but all ports are open
  if ! iptables -S | grep -v ACCEPT ; then
    echo "no iptables rules, all ports are open on $HOSTNAME"
    return 0
  fi

  # there are some iptables rules, verify the required ports are open
  local out; local port; local proto
  local out; local errcnt=0; local warncnt=0
  declare -A PORTS=$($PREFIX/gen_ports.sh)

  for proto in ${!PORTS[@]}; do
      for port in ${PORTS[$proto]}; do
	  # live check
	  if ! match_port_live $port $proto ; then
	    echo "ERROR on $NODE: iptables: port(s) $port not open"
	    ((errcnt++))
	  fi
	  # file check
	  if ! match_port_conf $port $proto ; then
	    echo "WARN on $NODE: $iptables_conf file: port(s) $port not accepted"
	    ((warncnt++))
	  fi
      done
  done

  (( errcnt > 0 )) && return 1
  echo "all required ports are open on $NODE with $warncnt warnings"
  return 0
}

# check_ntp: verify that ntp is running and the config file has 1 or more
# suitable server records.
function check_ntp() {

  local errcnt=0; local warncnt=0

  validate_ntp_conf || ((errcnt++))

  # is ntpd configured to run on reboot?
  chkconfig ntpd 
  if (( $? != 0 )); then
    echo "WARN: ntpd not configured to run on reboot"
    ((warncnt++))
  fi

  # verify that ntpd is running
  ps -C ntpd >& /dev/null
  if (( $? != 0 )) ; then
    echo "ERROR: ntpd is not running"
    ((errcnt++))
  fi

  (( errcnt > 0 )) && return 1
  echo "ntpd is running on $NODE with $warncnt warnings"
  return 0
}

# check_selinux: if selinux is enabled then set it to permissive.
function check_selinux() {

  local out; local errcnt=0

  # report selinux state
  out=$(sestatus | head -n 1 | awk '{print $3}') # enforcing, permissive
  echo "selinux on $NODE is set to: $out"
 
  [[ "$out" == 'enabled' ]] && ((errcnt++))

  (( errcnt > 0 )) && return 1
  echo "selinux configured correctly on $NODE"
  return 0
}

# check_users: check that the required hadoop-specific users are present on
# this node. This function does NOT check for UID consistency across the pool.
function check_users() {

  local user; local errcnt=0; local warncnt=0

  for user in $($PREFIX/gen_users.sh); do
      getent passwd $user >& /dev/null && continue
      echo "ERROR: $user is missing from $NODE"
      ((errcnt++))
  done

  (( errcnt > 0 )) && return 1
  echo "all required users present on $NODE with $warncnt warnings"
  return 0
}

# check_xfs:
function check_xfs() {

  local err; local errcnt=0; local warncnt=0; local out; local isize=512

  if [[ ! -d $BRICKMNT ]] ; then
    echo "ERROR: directory $BRICKMNT missing on $NODE"
    ((errcnt++))
  else
    xfs_info $BRICKMNT 2>&1
    err=$?
    if (( err != 0 )) ; then
      echo "ERROR $err:xfs_info on $BRICKMNT"
      ((errcnt++))
    else
      out="$(cut -d' ' -f2 <<<$out | cut -d'=' -f2)" # isize value
      if (( out != $isize )) ; then
        echo "WARN: xfs for $BRICKMNT on $NODE expected to be $isize in size; instead sized at $out"
	((warncnt++))
      fi
    fi
  fi

  (( errcnt > 0 )) && return 1
  echo "xfs setup correctly on $NODE with $warncnt warnings"
  return 0
}


## main ##

errcnt=0
NODE="$HOSTNAME"
BRICKMNT="$1" # includes the vol name in path
[[ -z "$BRICKMNT" ]] && {
  echo "Syntax error: xfs brick mount path is required";
  exit -1; }

check_xfs          || ((errcnt++))
check_brick_mount  || ((errcnt++))
check_selinux      || ((errcnt++))
check_open_ports   || ((errcnt++))
check_ntp          || ((errcnt++))
check_users        || ((errcnt++))
check_dirs         || ((errcnt++))
check_ambari_agent || ((errcnt++))

(( errcnt > 0 )) && exit 1
echo '************'
echo "*** $NODE is ready for Hadoop workloads"
echo '************'
echo
exit 0
