#!/bin/bash
#
# set_glusterfs_uri.sh updates the hadoop core-site.xml file with the passed-in
# volume name and volume mount path. The volume name is prepended to the list
# of volumes specified in the "fs.glusterfs.volumes" property, which makes this
# volume the *default* volume for unqualfied file references. If this volume
# is not the desired default volume then the user must manually change the
# order of the volume names. See Ambari -> GlusterFS -> Configs.
#
# Syntax: see usage() function.

PREFIX="$(dirname $(readlink -f $0))"
_DEBUG="off"
USERID="admin"
PASSWD="admin"
PORT=":8080"
PARAMS='' # used only for debugging
AMBARI_HOST='localhost'
VOLNAME=''
CLUSTER_NAME=""

# debug: execute cmd in $1 if _DEBUG is set to 'on'.
# Uses globals:
#   _DEBUG
function debug() {
 [ "$_DEBUG" == "on" ] &&  $@
}

# usage: echos general usage paragraph.
function usage() {
  echo "Usage: set_glusterfs_uri.sh [-u userId] [-p password] [--port port] [-h ambari_host] <VOLNAME>"
  echo ""
  echo "       [-u userId]: Optional user ID to use for authentication. Default is 'admin'."
  echo "       [-p password]: Optional password to use for authentication. Default is 'admin'."
  echo "       [--port port]: Optional port number for Ambari server. Default is '8080'. Provide empty string to not use port."
  echo "       [--mountpath path]: Required mount path for the volume."
  echo "       [-h ambari_host]: Optional external host name for Ambari server. Default is 'localhost'."
  echo "       VOLNAME: Gluster Volume name."
  exit 1
}

# parse_cmd: parses the command line via getopt. Returns 1 on errors. Sets the
# following globals:
#   AMBARI_HOST
#   _DEBUG
#   DEBUG
#   MOUNTPATH
#   PASSWD
#   PORT
#   USERID
#   VOLNAME
function parse_cmd() {

  local OPTIONS='u:p:h:'
  local LONG_OPTS='port:,mountpath:,help,debug'

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
		PARAMS="$PARAMS -port $2 "
		shift 2; continue
	;;
	--mountpath)
		MOUNTPATH="$2" # volname is appended to mountpath
		shift 2; continue
	;;
	--debug)
		DEBUG=true; _DEBUG="on"; shift; continue
	;;
	-u)
		USERID="$2"
		PARAMS="-u $USERID "
		shift 2; continue
	;;
	-p)
		PASSWD="$2"
		PARAMS="$PARAMS -p $PASSWD "
		shift 2; continue
	;;
	-h)
		[[ -n "$2" ]] && AMBARI_HOST="$2"
		shift 2; continue
	;;
	--) # no more args to parse
		shift; break
	;;
	*) echo "Error: Unknown option: \"$1\""; return 1
	;;
      esac
  done
  
  # error if more than one arg
  (( $# > 1 )) && {
    echo "Error: Unknown values: \"$@\""; usage; return 1; }

  VOLNAME="$1"
  [[ -z "$VOLNAME" ]] && {
    echo "Syntax error: VOLNAME is missing"; usage; return 1; }

  # error if required options are missing
  [[ -z "$MOUNTPATH" ]] && {
    echo "Syntax error: MOUNTPATH is missing"; usage; return 1; }

  [[ $DEBUG == true ]] && debug echo "DEBUGGING ON"

  return 0
}

# currentClusterName: sets the CLUSTER_NAME based on the value in the ambari
# config file. Returns 1 on errors.
# Set globals:
#   CLUSTER_NAME
function currentClusterName() {

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
  [[ -z "$value" ]] && {
    echo "ERROR: Cluster not found";
    return 1; }

  CLUSTER_NAME="$value"
  return 0
}

function restartService() {
# Note: the order of the services in both for loops below matters.

  local service

  for service in MAPREDUCE2 YARN GLUSTERFS ; do # order matters
      $PREFIX/ambari_service.sh -u $USERID -p $PASSWD --port $PORT \
	  -h $AMBARI_HOST --action stop $service
  done
  
  for service in GLUSTERFS MAPREDUCE2 YARN ; do # order matters
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
debug echo "########## AMBARIURL = $AMBARIURL"

currentClusterName || exit 1
debug echo "########## CLUSTER_NAME = $CLUSTER_NAME"

PARAMS="$PARAMS add_volume $AMBARI_HOST $CLUSTER_NAME core-site $VOLNAME"
PARAMS="$(echo $PARAMS | sed 's/\"//g')"
debug echo "########## PARAMS = $PARAMS"
	
PORT="$(echo "$PORT" | sed 's/[\"\,\:\ ]//g')"
CONFIG_UPDATE_PARAM="-u $USERID -p $PASSWD --port $PORT -h $AMBARI_HOST --config core-site --action add --configkey fs.glusterfs.volumes --configvalue $VOLNAME"
[[ $DEBUG == true ]] && CONFIG_UPDATE_PARAM+=" --debug"

debug echo "ambari_config_update.sh $CONFIG_UPDATE_PARAM" 
$PREFIX/ambari_config_update.sh "$CONFIG_UPDATE_PARAM" 

CONFIG_SET_PARAM="-u $USERID -p $PASSWD -port $PORT set $AMBARI_HOST $CLUSTER_NAME core-site fs.glusterfs.volume.fuse.$VOLNAME $MOUNTPATH"
debug echo "ambari_config.sh $CONFIG_SET_PARAM"
$PREFIX/ambari_config.sh $CONFIG_SET_PARAM
restartService

exit 0
