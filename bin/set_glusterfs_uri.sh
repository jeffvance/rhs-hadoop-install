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


# debug: execute cmd in $1 if _DEBUG is set to 'on'.
# Uses globals:
#   _DEBUG
function debug() {
 [ "$_DEBUG" == "on" ] &&  $@
}

# usage: echos general usage paragraph.
function usage() {

  cat <<EOF

Usage: set_glusterfs_uri.sh [-u <ambari-user>] [-p <password>] \\
         [-h <ambari-host>] [--port <port>] [-c <cluster-name>] \\
         --mountpath <path> --action <verb> <VOLNAME>

ambari-user : Optional. Ambari user ID. Default is "admin".
password    : Optional. Ambari password. Default is "admin".
ambari_host : Optional. Host name for the Ambari server. To use https a url must
              be provided as the host, eg. "https://ambari.vm". Default is
              localhost over http.
port        : Optional. Port number for Ambari server. Default is 8080 for http
              and 8443 for https.
cluster-name: Optional. The name of the current cluster.
path        : Required. Mount path for the volume when the action is prepend or
              append. Not used for the remove action.
verb        : Required. action to perform to property value:
              prepend|append|remove.
VOLNAME     : Required. RHS volume to be enabled/disabled.

EOF
  exit 1
}

# parse_cmd: parses the command line via getopt. Returns 1 on errors. Sets the
# following globals:
#   ACTION
#   AMBARI_HOST
#   CLUSTER_NAME
#   _DEBUG
#   DEBUG
#   MOUNTPATH
#   PASSWD
#   PORT
#   PROTO
#   USERID
#   VOLNAME
function parse_cmd() {

  local OPTIONS='u:p:h:c:'
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
		PORT=$2
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
	-c)
		CLUSTER_NAME="$2"
		shift 2; continue
	;;
	-u)
		USERID="$2"
		shift 2; continue
	;;
	-p)
		PASSWD="$2"
		shift 2; continue
	;;
	-h)
		AMBARI_HOST="$2"
 		if [[ "${AMBARI_HOST:0:8}" == 'https://' || \
		      "${AMBARI_HOST:0:7}" == 'http://' ]] ; then
		  PROTO="${AMBARI_HOST%://*}://"
		  AMBARI_HOST="${AMBARI_HOST#*://}" # exclude protocol
		fi
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
  if [[ -z "$ACTION" ]] ; then
    echo "Syntax error: action verb is missing"
    usage
    return 1
  fi
  case "$ACTION" in
      append|prepend|remove) # expected...
      ;;
      *)
	echo "Syntax error: action expected to be: prepend|append|remove"
	usage
	return 1
      ;;
  esac

  # error if required options are missing
  [[ -z "$MOUNTPATH" && "$ACTION" != 'remove' ]] && {
    echo "Syntax error: MOUNTPATH is missing"; usage; return 1; }

  # set default port
  if [[ -z "$PORT" ]] ; then
    [[ "$PROTO" == 'http://' ]] && PORT=8080 || PORT=8443
  fi

  [[ $DEBUG == true ]] && debug echo "DEBUGGING ON"
  return 0
}

function restartService() {
# Note: the order of the services in both for loops below matters.

  local service

  for service in MAPREDUCE2 YARN GLUSTERFS ; do # order matters
      $PREFIX/ambari_service.sh -u $USERID -p $PASSWD --port $PORT \
	  -h $AMBARIURL --cluster "$CLUSTER_NAME" --action stop $service
  done
  
  for service in GLUSTERFS MAPREDUCE2 YARN ; do # order matters
      $PREFIX/ambari_service.sh -u $USERID -p $PASSWD --port $PORT \
	  -h $AMBARIURL --cluster "$CLUSTER_NAME" --action start $service
  done
}


## ** main ** ##

# defaults (global variables)
SCRIPT=$0
DEBUG=false
_DEBUG="off"
USERID="admin"
PASSWD="admin"
PROTO='http://'
AMBARI_HOST='localhost'
VOLNAME=''
CLUSTER_NAME=''

parse_cmd $@ || exit -1

AMBARIURL="$PROTO$AMBARI_HOST"
debug echo "########## AMBARIURL = $AMBARIURL"

if [[ -z "$CLUSTER_NAME" ]] ; then
  CLUSTER_NAME="$(
	$PREFIX/find_cluster_name.sh $AMBARIURL:$PORT $USERID:$PASSWD)" || {
    echo "$CLUSTER_NAME"; # contains error msg
    exit 1; }
fi
debug echo "########## CLUSTER_NAME = $CLUSTER_NAME"

# update the fs.glusterfs.volumes attribute
CMD="-u $USERID -p $PASSWD -h $AMBARIURL --port $PORT \
    --cluster "$CLUSTER_NAME" --config core-site \
    --configkey fs.glusterfs.volumes --configvalue $VOLNAME --action $ACTION"
[[ $DEBUG == true ]] && CMD+=" --debug"

debug echo "ambari_config_update.sh $CMD" 
$PREFIX/ambari_config_update.sh $CMD 
(( $? != 0 )) && {
  echo "Error returned by ambari_config_update"; exit 1; }

# add or delete the fs.glusterfs.volume.fuse.<volname> property
mode='add'
[[ "$ACTION" == 'remove' ]] && mode='delete'
CMD="-u $USERID -p $PASSWD -h $AMBARIURL --port $PORT \
    --cluster "$CLUSTER_NAME" --config core-site \
    --configkey fs.glusterfs.volume.fuse.$VOLNAME --action $mode"
[[ "$mode" == 'add' ]] && CMD+=" --configvalue $MOUNTPATH"

debug echo "ambari_config_update.sh $CMD" 
$PREFIX/ambari_config_update.sh $CMD 
(( $? != 0 )) && {
  echo "Error returned by ambari_config_update"; exit 1; }

restartService
exit 0
