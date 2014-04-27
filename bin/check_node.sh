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

  local AMBARI_AGENT_PID='/var/run/ambari-agent/ambari-agent.pid'

  if [[ -f $AMBARI_AGENT_PID ]] ; then
    echo "ambari-agent is running on $NODE"
    return 0
  fi
  echo "ambari-agent is not running on $NODE"
  return 1
}

# check_open_ports: verify that the ports needed by gluster and ambari are all
# open.
function check_open_ports() {

  local errcnt=0; local port; local PORTS

  PORTS="$($prefix/gen_gluster_ports.sh)"

  for port in $PORTS; do # port can be a rang, a-c
      nc -z localhost $port
      if (( $? != 0 )) ; then
	echo "ERROR: port(s) $port not open. This port is needed by gluster"
	((errcnt++))
      fi
  done

  (( errcnt > 0 )) && return 1
  echo "The following ports are all open: $PORTS"
  return 0
}

function check_ntp() {



}

# check_selinux: if selinux is enabled then set it to permissive.
function check_selinux() {

  local out; local ENABLED='enabled'

  # report selinux state
  out=$(sestatus | head -n 1 | awk '{print $3}') # enforcing, permissive
  echo
  echo "on $NODE: SElinux is set: $out"
 
  [[ "$out" != "$ENABLED" ]] && return 0 # ok
  return 1
}


## main ##
NODE="$(hostname)"

# parse cmd opts
while getopts ':q' opt; do
    case "$opt" in
      q)
        quiet='-q'
        shift
        ;;
      \?) # invalid option
        shift # silently ignore opt
        ;;
    esac
done

prefix="$(dirname $(readlink -f $0))"
[[ ${prefix##*/} != 'bin' ]] && prefix+='/bin'

check_selinux

check_open_ports

check_ntp

check_ambari_agent
