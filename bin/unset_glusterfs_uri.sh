#!/bin/bash
#
# unset_glusterfs_uri.sh updates the hadoop core-site.xml file
#
# Syntax: see usage() function.

PREFIX="$(dirname $(readlink -f $0))"
_DEBUG="off"
USERID="admin"
PASSWD="admin"
PORT=":8080"
PARAMS=''
AMBARI_HOST='localhost'
VOLNAME=''
CLUSTER_NAME=""

# debug: execute cmd in $1 if _DEBUG is set to 'on'.
# Uses globals:
#   _DEBUG
function debug()
{
 [ "$_DEBUG" == "on" ] &&  $@
}

# usage: echos general usage paragraph.
function usage () {
  echo "Usage: unset_glusterfs_uri.sh [-u userId] [-p password] [--port port] [-h ambari_host] <VOLNAME>"
  echo ""
  echo "       [-u userId]: Optional user ID to use for authentication. Default is 'admin'."
  echo "       [-p password]: Optional password to use for authentication. Default is 'admin'."
  echo "       [--port port]: Optional port number for Ambari server. Default is '8080'. Provide empty string to not use port."
  echo "       [-h ambari_host]: Optional external host name for Ambari server. Default is 'localhost'."
  echo "       VOLNAME: Gluster Volume name."
  exit 1
}

# parse_cmd: parses the command line via getopt. Returns 1 on errors. Sets the
# following globals:
#   AMBARI_HOST
#   _DEBUG
#   DEBUG
#   PASSWD
#   PORT
#   USERID
#   VOLNAME
function parse_cmd(){

  local OPTIONS='u:p:h:'
  local LONG_OPTS='port:,help,debug'

  local args=$(getopt -n "$SCRIPT" -o $OPTIONS --long $LONG_OPTS -- $@)
  (( $? == 0 )) || { echo "$SCRIPT syntax error"; exit -1; }

  eval set -- "$args" # set up $1... positional args

  while true ; do
	case "$1" in
	--help)
		usage; exit 0
	;;
	--port)
		if [[ -z "$2" ]]; then
		  PORT=""
		else
		  PORT=":$2"
		fi
		debug echo "PORT=$2"
		PARAMS=$PARAMS" -port $2 "
		shift 2; continue
	;;
	--debug)
		DEBUG=true;_DEBUG="on"; shift; continue
	;;
	-u)
		USERID="$2"
                debug echo "USERID=$USERID"
		PARAMS="-u $USERID "
		shift 2; continue
	;;
	-p)
		PASSWD="$2"
		debug echo "PASSWORD=$PASSWD"
		PARAMS=$PARAMS" -p $PASSWD "
		shift 2; continue
	;;
	-h)
		[[ -n "$2" ]] && AMBARI_HOST="$2"
		debug echo "AMBARI_HOST=$2"
		shift 2; continue
	;;
	--) # no more args to parse
		shift; break
	;;
	*) echo "Error: Unknown option: \"$1\""; return 1
	;;
      esac
  done
  
  #take care of all other arguments
  if (( $# > 1 )); then
    echo "Error: Unknown values: \"$@\""; return 1
  fi
  if [[ -z "$1" ]]; then
    echo "Syntax error: VOLNAME is missing: \"$@\""; usage; return 1
  else
    VOLNAME="$1"
  fi

  eval set -- "$@" # move arg pointer so $1 points to next arg past last opt

  [[ $DEBUG == true ]] && debug echo "DEBUGGING ON"

  return 0
}

# currentClusterName: sets the CLUSTER_NAME based on the value in the ambari
# config file. Returns 1 on errors.
# Set globals:
#   CLUSTER_NAME
function currentClusterName () {

  local line=`curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/" | grep -E "cluster_name" | sed "s/\"//g"`
  local line1; local propLen; local lastChar
  local key; local value; local keyvalue=()

  if [[ -z "$line" ]]; then
    echo "ERROR: Cluster was not found in server response."
    return 1
  fi

  debug echo "########## LINE = "$line

  line1="$line"
  propLen=${#line1}
  lastChar=${line1:$propLen-1:1}
  [[ "$lastChar" == "," ]] && line1=${line1:0:$propLen-1}

  OIFS="$IFS"
  IFS=':'
  read -a keyvalue <<< "$line1"
  IFS="$OIFS"
  key=${keyvalue[0]}
  value="${keyvalue[1]}"

  value=$(echo "$value" | sed "s/[\"\,\ ]//g")
  debug echo "########## VALUE = "$value
  if [[ ! -z "$value" ]]; then   
    CLUSTER_NAME="$value"
  else
    echo "ERROR: Cluster not found"
    return 1
  fi 
}

function restartService() {

  local service

  for service in MAPREDUCE2 YARN HDFS; do
      $PREFIX/ambari_service.sh -u $USERID -p $PASSWD --port $PORT \
	  -h $AMBARI_HOST --action stop $service
  done
  
  for service in HDFS MAPREDUCE2 YARN ; do
      $PREFIX/ambari_service.sh -u $USERID -p $PASSWD --port $PORT \
	  -h $AMBARI_HOST --action start $service
  done
}


## ** main ** ##

# defaults (global variables)
DEBUG=false
SCRIPT=$0

parse_cmd $@ || exit -1

AMBARIURL="http://$AMBARI_HOST$PORT"
debug echo "########## AMBARIURL = "$AMBARIURL

currentClusterName || exit 1
debug echo "########## CLUSTER_NAME = "$CLUSTER_NAME

PARAMS=$PARAMS" remove_volume $AMBARI_HOST $CLUSTER_NAME core-site "$VOLNAME
PARAMS=`echo $PARAMS | sed "s/\"//g"`
debug echo "########## PARAMS = "$PARAMS
	
PORT=$(echo "$PORT" | sed "s/[\"\,\:\ ]//g")
CONFIG_UPDATE_PARAM="-u $USERID -p $PASSWD --port $PORT -h $AMBARI_HOST --config core-site --action remove --configkey fs.glusterfs.volumes --configvalue $VOLNAME"
[[ $DEBUG == true ]] && CONFIG_UPDATE_PARAM=$CONFIG_UPDATE_PARAM" --debug"

debug echo "./ambari_config_update.sh $CONFIG_UPDATE_PARAM"
$PREFIX/ambari_config_update.sh "$CONFIG_UPDATE_PARAM" 

CONFIG_DELETE_PARAM="-u $USERID -p $PASSWD -port $PORT delete $AMBARI_HOST $CLUSTER_NAME core-site fs.glusterfs.volume.fuse.$VOLNAME"
debug echo "./config.sh $CONFIG_DELETE_PARAM"
$PREFIX/ambari_config.sh $CONFIG_DELETE_PARAM
restartService

exit 0
