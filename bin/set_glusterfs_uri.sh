#!/bin/bash
#
# set_glusterfs_uri.sh updates the hadoop core-site.xml file with the passed-in
# volume name and volume mount path (which is required for the prepend and
# append actions). Depending on the action, the volume name is prepended,
# appended, or deleted to/from the list of volumes specified in the
# "fs.glusterfs.volumes" property. Additionally, the volume/fuse mount property
# is either created or deleted in core-site.
#
# NOTE: the first volume appearing in "fs.glusterfs.volumes" becomes the
#   default volume and will be used for all unqualified URI/file references.
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
  echo "Usage: set_glusterfs_uri.sh [-u userId] [-p password] [--port port] [-h ambari_host] --mountpath <path> --action <verb> <VOLNAME>"
  echo ""
  echo "       [--action verb]: Required action/verb to perform to property value: prepdend|append|remove."
  echo "       [-u userId]: Optional user ID to use for authentication. Default is 'admin'."
  echo "       [-p password]: Optional password to use for authentication. Default is 'admin'."
  echo "       [--port port]: Optional port number for Ambari server. Default is '8080'. Provide empty string to not use port."
  echo "       [--mountpath path]: mount path for the volume when the action is prepend or append. Not used for the removee action"
  echo "       [-h ambari_host]: Optional external host name for Ambari server. Default is 'localhost'."
  echo "       VOLNAME: Gluster Volume name."
  exit 1
}

# parse_cmd: parses the command line via getopt. Returns 1 on errors. Sets the
# following globals:
#   ACTION
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
  local LONG_OPTS='port:,mountpath:,action:,help,debug'

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
	--action)
		ACTION="$2"
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

  # error is unexpected action
  [[ -z "$ACTION" ]] && {
    echo "Syntax error: action/verb is missing"; usage; return 1; }
  [[ "$ACTION" != 'prepend' && "$ACTION" != 'append' && \
     "$ACTION" != 'remove' ]] && {
    echo "Syntax error: action expected to be: prepend|append|remove";
    usage; return 1; }

  # error if required options are missing
  [[ -z "$MOUNTPATH" && "$ACTION" != 'remove' ]] && {
    echo "Syntax error: MOUNTPATH is missing"; usage; return 1; }

  [[ $DEBUG == true ]] && debug echo "DEBUGGING ON"
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

CLUSTER_NAME="$(
	$PREFIX/find_cluster_name.sh $AMBARIURL "$USERID:$PASSWD")" || {
  echo "$CLUSTER_NAME"; # contains error msg
  exit 1; }
debug echo "########## CLUSTER_NAME = $CLUSTER_NAME"

PARAMS="$PARAMS add_volume $AMBARI_HOST $CLUSTER_NAME core-site $VOLNAME"
PARAMS="$(echo $PARAMS | sed 's/\"//g')"
debug echo "########## PARAMS = $PARAMS"
	
PORT="$(echo "$PORT" | sed 's/[\"\,\:\ ]//g')"
CONFIG_UPDATE_PARAM="-u $USERID -p $PASSWD --port $PORT -h $AMBARI_HOST --config core-site --action $ACTION --configkey fs.glusterfs.volumes --configvalue $VOLNAME"
[[ $DEBUG == true ]] && CONFIG_UPDATE_PARAM+=" --debug"

debug echo "ambari_config_update.sh $CONFIG_UPDATE_PARAM" 
$PREFIX/ambari_config_update.sh "$CONFIG_UPDATE_PARAM" 

mode='set'
[[ "$ACTION" == 'remove' ]] && mode='delete'
CONFIG_SET_PARAM="-u $USERID -p $PASSWD -port $PORT $mode $AMBARI_HOST $CLUSTER_NAME core-site fs.glusterfs.volume.fuse.$VOLNAME"
[[ "$mode" == 'set' ]] && CONFIG_SET_PARAM+=" $MOUNTPATH"

debug echo "ambari_config.sh $CONFIG_SET_PARAM"
$PREFIX/ambari_config.sh $CONFIG_SET_PARAM

restartService

exit 0
