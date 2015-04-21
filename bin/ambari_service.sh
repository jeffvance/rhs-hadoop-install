#!/bin/bash
#
# ambari_service.sh used to start stop a service.
#
# Syntax: see usage() function.

PREFIX="$(dirname $(readlink -f $0))"

_DEBUG="off"
USERID="admin"
PASSWD="admin"
PROTO='http://'
AMBARI_HOST='localhost'
SERVICENAME=''
ACTION=""


# debug: execute cmd in $1 if _DEBUG is set to 'on'.
# Uses globals:
#   _DEBUG
function debug()
{
 [ "$_DEBUG" == "on" ] &&  $@
}

# usage: echos general usage paragraph.
function usage () {

  cat <<EOF

Usage: ambari_service.sh [-u <user>] [-p <password>] [--port <port>] \\
              [-h <ambari_host>] --cluster <name> --action <verb> \\
              <SERVICE>"

user       : Optional. Ambari user. Default is "admin".
password   : Optional. Ambari password. Default is "admin".
ambari_host: Optional. Host name for the Ambari server. To use https a url must 
             be provided as the host, eg. "https://ambari.vm". Default is
             localhost over http.
port       : Optional. Port number for Ambari server. Default is 8080 for http
             and 8443 for https.
name       : Required. The ambari cluster name.
verb       : Required. Action to be performed. Expected values: start|stop.
SERVICE    : Required. The ambari service to be stopped or started, eg. Yarn.

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
#   PASSWD
#   PORT
#   PROTO
#   SERVICENAME
#   USERID
function parse_cmd(){

  local errcnt=0
  local OPTIONS='u:p:h:'
  local LONG_OPTS='cluster:,port:,action:,debug'

  local args=$(getopt -n "$SCRIPT" -o $OPTIONS --long $LONG_OPTS -- $@)
  (( $? == 0 )) || { echo "$SCRIPT syntax error"; exit -1; }

  eval set -- "$args" # set up $1... positional args

  while true ; do
    case "$1" in
      --debug)
        DEBUG=true;_DEBUG="on"; shift; continue
      ;;
      --port)
        PORT=$2
        shift 2; continue
      ;;
      --cluster)
	CLUSTER_NAME="$2"
	shift 2; continue
      ;;
      --action)
	ACTION="$2"
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
        shift; break;
      ;;
      *) echo "Error: Unknown option: \"$1\""; return 1
      ;;
    esac
  done
  
  SERVICENAME="$1"

  # enforce required args and options
  [[ -z "$SERVICENAME" ]] && {
    echo "Syntax error: SERVICE is missing"; ((errcnt++)); }

  [[ -z "$CLUSTER_NAME" ]] && {
    echo "Syntax error: cluster name is missing"; ((errcnt++)); }

  [[ -z "$ACTION" ]] && {
    echo "Syntax error: ACTION is missing"; ((errcnt++)); }

  [[ "$ACTION" != 'start' && "$ACTION" != 'stop' ]] && {
    echo "Syntax error: ACTION expected to be start|stop"; ((errcnt++)); }

  (( errcnt > 0 )) && {
    usage; return 1; }

  # set default port
  if [[ -z "$PORT" ]] ; then
    [[ "$PROTO" == 'http://' ]] && PORT=8080 || PORT=8443
  fi

  eval set -- "$@" # move arg pointer so $1 points to next arg past last opt

  [[ $DEBUG == true ]] && debug echo "DEBUGGING ON"

  return 0
}

# startService: starts a service
# Returns 1 on errors.
startService () {
  local line
  local rid ;local value ;local output ;local service

  service=$1
  debug echo "########## service = "$service
  if curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME/services/$service" | grep state | cut -d : -f 2 | grep -q "STARTED" ; then
    echo "$service already started."
  else
    echo "Starting $service service"

    line=$(curl -s -u $USERID:$PASSWD -X PUT  -H "X-Requested-By: rhs" "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME/services?ServiceInfo/state=INSTALLED&ServiceInfo/service_name=$1" --data "{\"RequestInfo\": {\"context\" :\"Start $1 Service\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"STARTED\"}}}")
    
    debug echo "########## line = "$line
    value=$(echo $line |cut -d',' -f2 |cut -d":" -f3)
    value=$(echo $value | sed "s/\"//g")
    debug echo "########## value = ["$value"]"
    if [[ -z "$value" ]]; then
      return 1
    fi

    rid=$value
    #Check if request is successful
    debug echo "curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME/requests/$rid" |grep "request_status" |cut -d : -f 2 |  sed "s/[\"\,\ ]//g""
    while true
    do
      output=$(curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME/requests/$rid" |grep "request_status" |cut -d : -f 2 |  sed "s/[\"\,\ ]//g")
      debug echo "########## output = "$output 
      if [ "$output" == "PENDING" ] || [ "$output" == "IN_PROGRESS" ]
      then
        echo "Request is still $output ..."
        sleep 4
        continue
      else
        if [ "$output" != "COMPLETED" ] ; then
          echo "[ERROR] : Request is $output."
          return 1
        else
          echo "Request is $output."
        fi
        break
      fi
    done
  fi
}


# startService: starts a service
# Returns 1 on errors.
stopService () {
  local line
  local rid ;local value ;local output ;local service

  service=$1
  debug echo "########## service = "$service
  if curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME/services/$service" | grep state | cut -d : -f 2 | grep -q "INSTALLED" ; then
    echo "$service already stopped."
  else
    echo "Stopping $service service"

    line=$(curl -s -u $USERID:$PASSWD -X PUT  -H "X-Requested-By: rhs" "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME/services?ServiceInfo/state=STARTED&ServiceInfo/service_name=$1" --data "{\"RequestInfo\": {\"context\" :\"Start $1 Service\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"INSTALLED\"}}}")
    
    debug echo "########## line = "$line
    value=$(echo $line |cut -d',' -f2 |cut -d":" -f3)
    value=$(echo $value | sed "s/\"//g")
    debug echo "########## value = ["$value"]"
    if [[ -z "$value" ]]; then
      return 1
    fi

    rid=$value
    #Check if request is successful
    while true
    do
      output=$(curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME/requests/$rid" |grep "request_status" |cut -d : -f 2 |  sed "s/[\"\,\ ]//g")
      debug echo "curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME/requests/$rid" |grep "request_status" |cut -d : -f 2 |  sed "s/[\"\,\ ]//g""
      debug echo "########## output = "$output 
      if [ "$output" == "PENDING" ] || [ "$output" == "IN_PROGRESS" ]
      then
        echo "Request is still $output ..."
        sleep 4
        continue
      else
        if [ "$output" != "COMPLETED" ] ; then
          echo "[ERROR] : Request is $output."
          return 1
        else
          echo "Request is $output."
        fi
        break
      fi
    done
  fi
}



## ** main ** ##

# defaults (global variables)
DEBUG=false
SCRIPT=$0

parse_cmd $@ || exit -1

AMBARIURL="$PROTO$AMBARI_HOST:$PORT"
debug echo "########## AMBARIURL = "$AMBARIURL
debug echo "########## CLUSTER_NAME = "$CLUSTER_NAME
debug echo "########## SERVICENAME  = "$SERVICENAME
debug echo "########## ACTION = "$ACTION

[[ "$ACTION" == "start" ]] && {
  startService $SERVICENAME || exit 1; }
[[ "$ACTION" == "stop" ]] && {
  stopService $SERVICENAME || exit 1; }

exit 0
