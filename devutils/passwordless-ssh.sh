#
# Assumptions:
#
# See the usage() function for arguments and their definitions.

# set global variables
SCRIPT=$(/bin/basename $0)
SCRIPT_VERS='0.1'       # self version
INSTALL_DIR=$(pwd)      # name of deployment (install-from) dir
INSTALL_FROM_IP=$(hostname -i)
LOGFILE='/var/log/pwdless-ssh.log'

#set DEBUG flage to default value (can override with --debug | --nodebug)
DEBUG=true

# display: Write the message to stdlist and append it to localhost's logfile.
#
function display(){  # $1 is the message
  echo "$1" >> $LOGFILE
  echo -e "$1"
}

# bugout: Write out a debugging message
#
function bugout (){ # $1 is the message
   
   local output_string="DEBUG: "

   if [[ $DEBUG == true ]] ; then 
      output_string+=$1
      display "$output_string"
   fi

}

# short_usage: write short usage to stdout.
#
function short_usage(){

  echo -e "Syntax:\n"
  echo "$SCRIPT [-v|--version] | [-h|--help]"
  echo "$SCRIPT [--hosts <path>]"
  echo "$SCRIPT [--sethostname | [--noset|--nosethostname]"
  echo
}

# usage: write full usage/help text to stdout.
#
function usage(){

  echo
  echo -e "$SCRIPT (version $SCRIPT_VERS)  Usage:\n"
  echo "Setup password-less SSH as required for the RHS cluster."
  echo
  echo " ... add more explanation :)... "
  echo
  echo "  --hosts     <path> : path to \"hosts\" file. This file contains a list of"
  echo "                       \"IP-addr hostname\" pairs for each node in the cluster."
  echo "                       Default: \"./hosts\""
  echo "  -v|--version       : Version of the script"
  echo "  -h|--help          : help text (this)"
  echo "  --sethostname      : sethostname=hostname on each node (default)"
  echo "  --noset|nosethostname : do not set the hostname on each node (override default)"
  echo
}

# parse_cmd: getopt used to do general parsing. The brick-dev arg is required.
# The remaining parms are optional. See usage function for syntax.
#
function parse_cmd(){

  local OPTIONS='vh'
  local LONG_OPTS='hosts:,help,version,noset,nosethostnamem,debug,nodebug'

  # defaults (global variables)
  REPLICA_CNT=2
  SETHOSNAME=true
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
	    echo "$SCRIPT version: $INSTALL_VER"; exit 0
	;;
	--hosts)
	    HOSTS_FILE=$2; shift 2; continue
	;;
	--debug)
           DEBUG=true; shift; continue
	;;
	--nodebug)
           display "nodebug!!"; DEBUG=false; shift; continue
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
     display "DEBUGGING ON"
  fi
}

function read_verify_local_hosts_file(){

    local i; local host=''; local ip=''; local hosts_ary; local numTokens

    # regular expression to validate ip addresses
    local VALID_IP_RE='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'

    # regular expression to validate hostnames
    local VALID_HOSTNAME_RE='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'

    # read hosts file, skip comments and blank lines, parse out hostname and ip
    read -a hosts_ary <<< $(sed '/^ *#/d;/^ *$/d;s/#.*//' $HOSTS_FILE)
    numTokens=${#hosts_ary[@]}
    HOSTS=(); HOST_IPS=() # global vars

    # hosts file format: ip-address  hostname  # one pair per line
    for (( i=0; i<$numTokens; i++ )); do
	# IP address:
	ip=${hosts_ary[$i]}
        bugout "ip = $ip"

	# validate basic ip-addr syntax
	if [[ ! $ip =~ $VALID_IP_RE ]] ; then
	  errmsg+=" * $HOSTS_FILE record $((i/2)):\n   Unexpected IP address syntax for \"$ip\"\n"
	  ((errcnt++))
	  break # exit loop
	fi
	HOST_IPS+=($ip)

	# hostname:
	((i++))
	host=${hosts_ary[$i]}
        bugout "host = $host"

	# validate basic hostname syntax
 	if [[ ! $host =~ $VALID_HOSTNAME_RE ]] ; then
	  errmsg+=" * $HOSTS_FILE record $((i/2)):\n   Unexpected hostname syntax for \"$host\"\n"
	  ((errcnt++))
	  break # exit loop
        fi
	HOSTS+=($host)

        # verify connectivity from localhost to data node
	# note: ip used since /etc/hosts may not be set up to map ip to hostname
        bugout "--->checking to see if we already have password-less SSH"
	ssh -q -oBatchMode=yes root@$ip exit
        if (( $? != 0 )) ; then
           bugout "nope...no password-less SSH to $ip"
	fi
    done

    (( errcnt != 0 )) && return # errors in hosts checking loop are fatal

    # validate the number of nodes in the hosts file
    NUMNODES=${#HOSTS[@]}
    bugout "Number of nodes found in hostfile = $NUMNODES"
    if (( NUMNODES < REPLICA_CNT )) ; then
      errmsg+=" * The $HOSTS_FILE file must contain at least $REPLICA_CNT nodes (replica count)\n"
      ((errcnt++))
    elif (( NUMNODES % REPLICA_CNT != 0 )) ; then
      errmsg+=" * The number of nodes in the $HOSTS_FILE file must be a multiple of the\n   replica count ($REPLICA_CNT)\n"
      ((errcnt++))
    fi
  }

function setup_passwordless_ssh {

   local i; local host=''; local ip=''; local sshOK='OK'

   bugout "remove old id_rsa* key files"
   rm -f ~/.ssh/id_rsa*

   bugout "romove old known_hosts file"
   rm -f ~/.ssh/known_hosts

   display "Generating key: ssh-keygen -q -t rsa -f ~/.ssh/id_rsa -N ''"
   ssh-keygen -q -t rsa -f ~/.ssh/id_rsa -N ""


   display "Copying keys to each node..."
   for (( i=1; i<$NUMNODES; i++ )); do
       ip=${HOST_IPS[$i]}
       host=${HOSTS[$i]}
       bugout "--> $host ($ip)"

       if [[ $SETHOSTNAME == true ]] ; then 
          display "Setting Hostname for $host"
          bugout "--> with 'ssh root@$$ip sethostname $host' command"
          ssh root@$$ip sethostname $host
       fi
      
       display "Copying SSH keyfile to $host"
       bugout "---> with 'sh-copy-id -i ~/.ssh/id_rsa.pub root@$host' command"
       ssh-copy-id -i ~/.ssh/id_rsa.pub root@$host

       # test if passwordless SSH is working
       ssh -q -oBatchMode=yes root@$host exit
       if (( $? != 0 )) ; then
          sshOK = 'FAILED'
          display "PASSWORDLESS SSH SETUP FAILED - FATAL!"
          exit 20
       fi

       display "... NODE: $host (IP: $ip),SSH=$sshOK,SETHOSTNAME=$SETHOSTNAME"
   done

}


## ** main ** ##

display "$(/bin/date). Begin: $SCRIPT -- version $SCRIPT_VERS ***"

parse_cmd $@

display "Using host file: $HOSTS_FILE"
read_verify_local_hosts_file

display "Setting up passwordless SSH"
setup_passwordless_ssh

#
# end of script
