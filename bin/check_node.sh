#!/bin/bash
#
# check_node.sh verifies that the node running the script (localhost) is setup
# correctly for hadoop workloads. This includes everything other than volume-
# specific checks. So, we check: ntp config, required gluster and ambari ports
# being open, ambari agent running, selinux not enabled, hadoop users and dirs,
# etc...
#
# Syntax:
#  $1= volume mount directory prefix
#  -q, if specified, means only set the exit code, do not output anything

# Assumption: the node running this script can passwordless ssh to the node arg.

errcnt=0

function check_ambari_agent() {

  local ambari_agent_pid='/var/run/ambari-agent/ambari-agent.pid'

  if [[ -f $ambari_agent_pid ]] ; then
    [[ -z "$QUIET" ]] && echo "ambari-agent is running on $NODE"
    return 0
  fi
  [[ -z "$QUIET" ]] && echo "ambari-agent is not running on $NODE"
  return 1
}

# check_dirs: check that the required hadoop-specific directories are present
# on this node. Also check that the perms and owner are set correctly.
function check_dirs() {

  local dir; local perm; local owner; local tuple
  local out; local errcnt=0

  for tuple in $($PREFIX/gen_dirs.sh); do
      dir="$VOLMNT/${tuple%%:*}"
      perm=${tuple%:*}; perm=${perm#*:}
      owner=${tuple##*:}

      if [[ ! -d $dir ]] ; then
 	[[ -z "$QUIET" ]] && echo "ERROR: $dir is missing from $NODE"
	((errcnt++))
	continue
      fi

      # check dir's perms and owner
      out="$(stat -c %a $dir)"
      [[ ${#out} == 3 ]] && out="0$out"; # leading 0
      if [[ $out != $perm ]] ; then
 	[[ -z "$QUIET" ]] && \
	  echo "ERROR: $dir perms are $out, expected to be: $perm"
	((errcnt++))
      fi
      out="$(stat -c %U $dir)"
      if [[ $out != $owner ]] ; then
 	[[ -z "$QUIET" ]] && \
	  echo "ERROR: $dir owner is $out, expected to be: $owner"
	((errcnt++))
      fi
  done

  (( errcnt > 0 )) && return 1
  return 0
}

# check_open_ports: verify that the ports needed by gluster and ambari are all
# open.
function check_open_ports() {

  local out; local errcnt=0; local port; local proto; local ports

  ports="$($PREFIX/gen_ports.sh)"

  for port in $ports; do # "port:protocol", eg "49152-49170:tcp"
      proto=${port#*:} # remove port #
      port=${port%:*}  # remove protocol, port can be a range or single number
      [[ "$proto" == 'udp' ]] && proto='-u' || proto=''
      # attempt to bind to this port or to any port in a range of ports
      out="$(nc -z $proto localhost $port)"
      [[ -z "$QUIET" ]] && echo "$out"
      if (( $? != 0 )) ; then
	[[ -z "$QUIET" ]] && echo "port(s) $port not open"
	((errcnt++))
      fi
  done

  (( errcnt > 0 )) && return 1
  [[ -z "$QUIET" ]] && echo "The following ports are all open: $ports"
}

# validate_ntp_conf: validate the ntp config file by ensuring there is at least
# one time-server suitable for ntp use.
function validate_ntp_conf(){

  local timeserver; local i=1
  local ntp_conf='/etc/ntp.conf'
  local servers=(); local numServers

  servers=($(grep "^ *server " $ntp_conf|awk '{print $2}')) # time-servers 
  numServers=${#servers[@]}

  if (( numServers == 0 )) ; then
    [[ -z "$QUIET" ]] && echo "ERROR: no server entries in $ntp_conf"
    return 1 # can't continue validating this ntp config file
  fi

  for timeserver in "${servers[@]}" ; do
      [[ -z "$QUIET" ]] && echo "attempting ntpdate on $timeserver..."
      ntpdate -q $timeserver >& /dev/null
      (( $? == 0 )) && break # exit loop, found valid time-server
      ((i+=1))
  done

  if (( i > numServers )) ; then
    [[ -z "$QUIET" ]] && \
	echo "ERROR: no suitable time-servers found in $ntp_conf"
    return 1
  fi
  [[ -z "$QUIET" ]] && echo "NTP time-server $timeserver is acceptable"
}

# check_ntp: verify that ntp is running and the config file has 1 or more
# suitable server records.
function check_ntp() {

  local errcnt=0

  validate_ntp_conf || ((errcnt++))

  # is ntpd configured to run on reboot?
  chkconfig ntpd 
  if (( $? != 0 )); then
    [[ -z "$QUIET" ]] && echo "ERROR: ntpd not configured to run on reboot"
    ((errcnt++))
  fi

  # verify that ntpd is running
  ps -C ntpd >& /dev/null
  if (( $? != 0 )) ; then
    [[ -z "$QUIET" ]] && echo "ERROR: ntpd is not running"
    ((errcnt++))
  fi

  (( errcnt > 0 )) && return 1
  return 0
}

# check_selinux: if selinux is enabled then set it to permissive.
function check_selinux() {

  local out

  # report selinux state
  out=$(sestatus | head -n 1 | awk '{print $3}') # enforcing, permissive
  [[ -z "$QUIET" ]] && echo "SElinux is set: $out"
 
  [[ "$out" != 'enabled' ]] && return 0 # ok
  return 1
}

# check_users: check that the required hadoop-specific users are present on
# this node. This function does NOT check for UID consistency across the pool.
function check_users() {

  local user; local errcnt=0

  for user in $($PREFIX/gen_users.sh); do
      id -u $user >& /dev/null && continue
      [[ -z "$QUIET" ]] && echo "ERROR: $user is missing from $NODE"
      ((errcnt++))
  done

  (( errcnt > 0 )) && return 1
  return 0
}


## main ##
NODE="$(hostname)"

# parse cmd opts
while getopts ':q' opt; do
    case "$opt" in
      q)
        QUIET='-q'
        shift
        ;;
      \?) # invalid option
        shift # silently ignore opt
        ;;
    esac
done
VOLMNT="$1"

PREFIX="$(dirname $(readlink -f $0))"
[[ ${PREFIX##*/} != 'bin' ]] && PREFIX+='/bin'

check_selinux || ((errcnt++))

check_open_ports || ((errcnt++))

check_ntp || ((errcnt++))

check_users || ((errcnt++))

check_dirs || ((errcnt++))

check_ambari_agent || ((errcnt++))

(( errcnt > 0 )) && exit 1
[[ -z "$QUIET" ]] && echo "$NODE is ready for Hadoop workloads"
exit 0
