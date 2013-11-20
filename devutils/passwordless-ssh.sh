#! /bin/bash
#
# Set up password-less SSH based on contents of the local hosts file.
# See the usage() function for arguments and their definitions.

# set global variables
SCRIPT=$(/bin/basename $0)
SCRIPT_VERS='0.3'  # self version
INSTALL_DIR="$PWD" # name of deployment (install-from) dir

# source common constants and functions
. $INSTALL_DIR/functions


# bugout: Write out a debugging message.
#
function bugout (){ # $1 is the message
   
  local output_string="DEBUG: "

  if [[ $DEBUG == true ]] ; then 
    output_string+=$1
    echo "$output_string"
  fi
}

# usage: write usage/help text to stdout.
#
function usage(){

  cat <<EOF

Version $SCRIPT_VERS.  Usage:

Syntax:

  $SCRIPT [options]

Sets up password-less SSH as required for the RHS cluster. A local "hosts"
file of "ip-address hostname" pairs contains the list of hosts for which
password-less SSH is configured. Additionally, the first host in this file
will be able to password-less SSH to all other hosts in the file. Thus,
after running this script the user will be able to password-less SSH from
localhost to all hosts in the hosts file, and from the first host to all
other hosts defined in the file.

"host" file format:
   IP-address   simple-hostname
   IP-address   simple-hostname ...

Options:

   --hosts     <path> : path to "hosts" file. This file contains a list of
                        "IP-addr hostname" pairs for each node in the cluster.
                        Default: "./hosts".
   -v|--version       : Version of the script.
   -h|--help          : help text (this).
   --sethostname      : sethostname=hostname on each node (default).
   --noset|nosethostname : do not set the hostname on each node (override
                        default).
   --verbose          : causes more output. Default is semi-quiet.
EOF
}

# parse_cmd: getopt used to do general parsing. The brick-dev arg is required.
# The remaining parms are optional. See usage function for syntax.
#
function parse_cmd(){

  local OPTIONS='vh'
  local LONG_OPTS='hosts:,help,version,noset,nosethostnamem,verbose'

  # defaults (global variables)
  REPLICA_CNT=2
  SETHOSTNAME=true
  DEBUG=false

  # "hosts" file concontains hostname ip-addr for all nodes in cluster
  HOSTS_FILE="$INSTALL_DIR/hosts"

  local args=$(getopt -n "$SCRIPT" -o $OPTIONS --long $LONG_OPTS -- $@)
  (( $? == 0 )) || { echo "$SCRIPT syntax error"; exit -1; }

  eval set -- "$args" # set up $1... positional args
  while true ; do
      case "$1" in
	-h|--help)
	    usage; exit 0
	;;
	-v|--version)
	    echo "$SCRIPT version: $SCRIPT_VERS"; exit 0
	;;
	--hosts)
	    HOSTS_FILE=$2; shift 2; continue
	;;
	--verbose)
           DEBUG=true; shift; continue
	;;
	--noset|--nosethostname)
	   SETHOSTNAME=false; shift; continue
	;;
	--sethostname)
	   SETHOSTNAME=true; shift; continue
	;;
	--)  # no more args to parse
	    shift; break
	;;
	*) echo "Error: Unknown option: \"$1\""; exit -1
	;;
      esac
  done

  eval set -- "$@" # move arg pointer so $1 points to next arg past last opt

  if [[ $DEBUG == true ]] ; then 
     echo "DEBUGGING ON"
  fi
}

function setup_passwordless_ssh {

   local i; local host=''; local ip=''; local sshOK='OK'
   local KNOWN_HOSTS=~/.ssh/known_hosts # note: cannot quote value!
   local PRIVATE_KEY_FILE=~/.ssh/id_rsa # note: cannot quote value!

   if [[ ! -f $PRIVATE_KEY_FILE ]] ; then # on localhost...
     echo "Generating key: ssh-keygen -q -t rsa -f $PRIVATE_KEY_FILE -N ''"
     ssh-keygen -q -t rsa -f $PRIVATE_KEY_FILE -N ""
   fi

   # add hosts "hosts" file to local /etc/hosts if not already there
   echo "Potentially update /etc/hosts with hostnames..."
   fixup_etc_hosts_file

   echo "Copying keys to each node..."
   for (( i=0; i<$NUMNODES; i++ )); do
	ip=${HOST_IPS[$i]}
	host=${HOSTS[$i]}
	bugout "--> $host ($ip)"

	# remove host and ip from known_hosts file, if present
	bugout "delete \"$host\" and/or \"$ip\" from known_hosts file"
	[[ -f $KNOWN_HOSTS ]] && sed -i "/^$host/d;/^$ip/d" $KNOWN_HOSTS

	echo "Copying SSH keyfile to $host"
	bugout "---> with 'sh-copy-id -i ~/.ssh/id_rsa.pub root@$host' command"
	echo "** Answer \"yes\" to the '...continue connecting' prompt, and"
	echo "   enter the password for each node..."
	ssh-copy-id -i ~/.ssh/id_rsa.pub root@$host # user will be prompted

	# test if passwordless SSH is working
	ssh -q -oBatchMode=yes root@$host exit
	if (( $? != 0 )) ; then
          sshOK='FAILED'
          echo "PASSWORDLESS SSH SETUP FAILED - FATAL!"
          exit 20
	fi

	if [[ $SETHOSTNAME == true ]] ; then 
          echo "Setting hostname for $host"
          bugout "--> with 'ssh root@$ip hostname $host' command"
          ssh root@$ip hostname $host
	fi

	echo "...Node: $host (IP: $ip), SSH=$sshOK"
        echo
   done

   # set up passwordless-ssh from 1st host in the hosts file to all the other
   # hosts in that file.
   firstHost=${HOSTS[0]}
   echo "Last, set up passwordless-ssh from $firstHost to all other nodes"
   echo "in the hosts file"
   bugout "---> with 'scp ~/.ssh/id_* $KNOWN_HOSTS root@$firstHost:/root/.ssh'"
   scp ~/.ssh/id_* $KNOWN_HOSTS root@$firstHost:/root/.ssh
   for (( i=1; i<$NUMNODES; i++ )); do
	ip=${HOST_IPS[$i]}; host=${HOSTS[$i]}
	# append ip/host to first-node's /etc/hosts file
	bugout "---> with 'ssh root@$firstHost echo \"$ip $host\" >>/etc/hosts'"
	ssh root@$firstHost "echo '$ip $host' >>/etc/hosts"
	# copy id
	bugout "---> with 'ssh root@$firstHost ssh-copy-id -i ~/.ssh/id_rsa.pub root@$host'"
	ssh root@$firstHost "ssh-copy-id -i ~/.ssh/id_rsa.pub root@$host"
   done
}


## ** main ** ##

parse_cmd $@

echo "$(/bin/date). Begin: $SCRIPT -- version $SCRIPT_VERS ***"

echo "Using host file: $HOSTS_FILE"
verify_local_deploy_setup

echo "Begin setup of passwordless SSH"
setup_passwordless_ssh

#
# end of script
