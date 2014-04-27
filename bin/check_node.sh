#!/bin/bash
#
# check_node.sh verifies that the node running the script (localhost) is setup
# correctly for hadoop workloads. This includes everything other than volume-
# specific checks. So, we check: ntp config, required gluster and ambari ports
# being open, ambari agent running, selinux not enabled...
#
# Syntax:
#  -q, if specified, means only set the exit code, do not output anything

# Assumption: the node running this script can passwordless ssh to the node arg.

function check_ambari_agent() {

  local ambari_agent_pid='/var/run/ambari-agent/ambari-agent.pid'

  if [[ -f $ambari_agent_pid ]] ; then
    [[ -z "$QUIET" ]] && echo "ambari-agent is running on $NODE"
    return 0
  fi
  [[ -z "$QUIET" ]] && echo "ambari-agent is not running on $NODE"
  return 1
}

# check_open_ports: verify that the ports needed by gluster and ambari are all
# open.
function check_open_ports() {

  local out; local errcnt=0; local port; local proto; local ports

  ports="$($PREFIX/gen_gluster_ports.sh)"

  for port in $ports; do # "port:protocol", eg "49152-49170:tcp"
      proto=${port#*:} # remove port #
      port=${port%:*}  # remove protocol, port can be a range or single number
      [[ "$proto" == 'udp' ]] && proto='-u' || proto=''
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

  if ! validate_ntp_conf ; then
    ((errcnt++))
  fi

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

PREFIX="$(dirname $(readlink -f $0))"
[[ ${PREFIX##*/} != 'bin' ]] && PREFIX+='/bin'

check_selinux

check_open_ports

check_ntp

check_ambari_agent
