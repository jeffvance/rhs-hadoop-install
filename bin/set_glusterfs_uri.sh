#!/bin/bash


errcnt=0;

_DEBUG="off"
USERID="admin"
PASSWD="admin"
PORT=":8080"
PARAMS=''
AMBARI_HOST='localhost'
VOLUME_ID=''
CLUSTER_NAME=""

function debug()
{
 [ "$_DEBUG" == "on" ] &&  $@
}

usage () {
  echo "Usage: set_glusterfs_uri.sh [-u userId] [-p password] [-port port] [-h ambari_host] <VOLUME_ID>";
  echo "";
  echo "       [-u userId]: Optional user ID to use for authentication. Default is 'admin'.";
  echo "       [-p password]: Optional password to use for authentication. Default is 'admin'.";
  echo "       [-port port]: Optional port number for Ambari server. Default is '8080'. Provide empty string to not use port.";
  echo "       [-h ambari_host]: Optional external host name for Ambari server. Default is 'localhost'.";
  echo "       [VOLUME_ID]: Gluster Volume ID.";
  exit 1;
}

function parse_cmd(){

  local OPTIONS='u:p:h:'
  local LONG_OPTS='port:,help,debug'

  # defaults (global variables)
  DEBUG=false
  SCRIPT=$0


  local args=$(getopt -n "$SCRIPT" -o $OPTIONS --long $LONG_OPTS -- $@)
  (( $? == 0 )) || { echo "$SCRIPT syntax error"; exit -1; }

  eval set -- "$args" # set up $1... positional args
  while true ; do
        #echo $1
	case "$1" in
	--help)
		usage; exit 0
	;;
	--port)
		if [ -z $2 ]; then
		  PORT="";
		else
		  PORT=":$2";
		fi
		debug echo "PORT=$2";
		PARAMS=$PARAMS" -port $2 "
		shift 2; continue
	;;
	--debug)
		DEBUG=true;_DEBUG="on"; shift; continue
	;;
	-u)
		USERID=$2;
                debug echo "USERID=$USERID";
		PARAMS="-u $USERID "
		shift 2; continue
	;;
	-p)
		PASSWD=$2;
		debug echo "PASSWORD=$PASSWD";
		PARAMS=$PARAMS" -p $PASSWD "
		shift 2; continue
	;;
	-h)
		if [ -z $2 ]; then
		  AMBARI_HOST=$AMBARI_HOST;
		else
		  AMBARI_HOST="$2";
		fi
		debug echo "AMBARI_HOST=$2";
		shift 2; continue
	;;
	--) # no more args to parse
		shift; break
	;;
	*) echo "Error: Unknown option: \"$1\""; exit -1
	;;
      esac
  done
  
  #take care off all other arguments
  if [[ $# -gt 1 ]]; then
    echo "Error: Unknown values: \"$@\""; exit -1
  fi
  if [ -z $1 ]; then
    echo "Syntax error: VOLUME_ID is missing: \"$@\"";usage; exit -1
  else
    VOLUME_ID="$1";
  fi

  eval set -- "$@" # move arg pointer so $1 points to next arg past last opt

  if [[ $DEBUG == true ]] ; then
	debug echo "DEBUGGING ON"
  fi
}

########################
## currentClusterName()
########################
currentClusterName () {

  line=`curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/" | grep -E "cluster_name" | sed "s/\"//g"`;
  if [ -z "$line" ]; then
    echo "[ERROR] Cluster was not found in server response.";
    exit 1;
  fi

  debug echo "########## LINE = "$line

  line1=$line
  propLen=${#line1}
  lastChar=${line1:$propLen-1:1}
  if [ "$lastChar" == "," ]; then
    line1=${line1:0:$propLen-1}
  fi

  OIFS="$IFS"
  IFS=':'
  read -a keyvalue <<< "${line1}"
  IFS="$OIFS"
  key=${keyvalue[0]}
  value="${keyvalue[1]}"

  value=`echo $value | sed "s/[\"\,\ ]//g"`
  debug echo "########## VALUE = "$value
  CLUSTER_NAME="$value" 
}



## ** main ** ##

parse_cmd $@

AMBARIURL="http://$AMBARI_HOST$PORT"
debug echo "########## AMBARIURL = "$AMBARIURL

currentClusterName
debug echo "########## CLUSTER_NAME = "$CLUSTER_NAME
PARAMS=$PARAMS" add_volume $AMBARI_HOST $CLUSTER_NAME core-site "$VOLUME_ID
PARAMS=`echo $PARAMS | sed "s/\"//g"`
debug echo "########## PARAMS = "$PARAMS
	
debug echo "sh ./ambari_config.sh $PARAMS"
sh ./ambari_config.sh $PARAMS	|| ((errcnt++))

(( errcnt > 0 )) && exit 1
exit 0
