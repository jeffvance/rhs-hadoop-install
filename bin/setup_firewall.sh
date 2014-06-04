#!/bin/bash
#
# setup_firewall.sh prepends iptables rules specific to opening up all ports
# needed by hadoop, and the supported hadoop services, ontop of RHS on this 
# (localhost) node. Output is simple: all ports are open. Input is more complex
# and consists of prepending many rules to the INPUT chain.
# NOTE: Java RMI ports (random ports) cannot be handled here as we do not know
#   their port number.

PREFIX="$(dirname $(readlink -f $0))"

## functions ##

source $PREFIX/functions

# setup_iptables: open ports for the known gluster, ambari and hadoop services
# by prepending the port to the INPUT rule chain. Note: we don't append since 
# there could be an existing DENY or DROP in the chain. Note: if iptables is
# not running then we don't restart the service. Returns 1 on errors.
function setup_iptables() {

  local err; local errcnt=0; local portcnt=0
  local port; local proto
  declare -A PORTS=$($PREFIX/gen_ports.sh)

  for proto in ${!PORTS[@]}; do
      for port in ${PORTS[$proto]}; do
	  # open this port or port range for the target protocol ONLY if not
	  # already open
	  if match_port_conf $port $proto ; then
	     echo "port $port already opened in config file"
	  else
	    #iptables -I INPUT 1 -m state --state NEW -m $proto -p $proto \
		#--dport $port -j ACCEPT 2>&1
	    iptables -I INPUT 1 -p $proto --dport $port -j ACCEPT 2>&1
	    err=$?
	    if (( err == 0 )) ; then
	      ((portcnt++))
	    else
	      echo "ERROR $err: iptables port $port"
	      ((errcnt++))
	    fi
	  fi
      done
  done
  
  if (( portcnt > 0 )); then # added at least 1 port rule
    service iptables save
    err=$?
    if (( err != 0 )) ; then
      echo "ERROR $err: iptables save"
      ((errcnt++))
    fi

    # if iptables is running then restart it, else leave it off
    if service iptables status >& /dev/null ; then
      service iptables restart
      err=$?
      if (( err != 0 )) ; then
	echo "ERROR $err: iptables restart"
	((errcnt++))
      fi
    fi
  fi

  (( errcnt > 0 )) && return 1
  return 0
}

# main #

setup_iptables || exit 1

echo "iptables configured and saved"
exit 0
