#!/bin/bash
#
# ambari_service.sh used to start stop a service.
#
# Syntax: see usage() function.

_DEBUG="off"
USERID="admin"
PASSWD="admin"
PORT=":8080"
PARAMS=''
AMBARI_HOST='localhost'
SERVICENAME=''
CLUSTER_NAME=""
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
  echo "Usage: ambari_service.sh [-u userId] [-p password] [--port port] [-h ambari_host] --action start|stop <SERVICENAME>"
  echo ""
  echo "       [-u userId]: Optional user ID to use for authentication. Default is 'admin'."
  echo "       [-p password]: Optional password to use for authentication. Default is 'admin'."
  echo "       [--port port]: Optional port number for Ambari server. Default is '8080'. Provide empty string to not use port."
  echo "       [-h ambari_host]: Optional external host name for Ambari server. Default is 'localhost'."
  echo "       --action start|stop : start/stop SERVICENAME"
  echo "       [SERVICENAME]: config property or property value."
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
#   ACTION
#   SERVICENAME
function parse_cmd(){

  local OPTIONS='u:p:h:'
  local LONG_OPTS='port:,action:,help,debug'

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
      --action)
        [[ -n "$2" ]] && ACTION="$2"
        debug echo "ACTION=$ACTION"
        shift 2; continue
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
        debug echo "parsing done"
        shift; break;
      ;;
      *) echo "Error: Unknown option: \"$1\""; return 1
      ;;
    esac
  done

  
  #take care of all other arguments
  #make sure property is there
  if (( $# == 0 )); then
    echo "Syntax error: [SERVICENAME] is missing"; usage ; return 1
  fi
  #make sure there is only one property
  if (( $# > 1 )); then
    echo "Syntax error:: Unknown values: \"$@\""; return 1
  fi

  if [[ -z "$1" ]]; then
    echo "Syntax error: SERVICENAME is missing: \"$@\""; usage ; return 1
  else
    SERVICENAME="$1"
  fi

  if [[ -z "$ACTION" ]]; then
    echo "Syntax error: ACTION is missing"; usage ; return 1
  fi

  ACTION=$(echo "$ACTION" | sed "s/[\"\,\ ]//g")
  if [ "$ACTION" == "start" ] || [ "$ACTION" == "stop" ]; then
   ACTION=$ACTION
  else
    echo "Syntax error: ACTION should be start|stop"; usage ; return 1
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

AMBARIURL="http://$AMBARI_HOST$PORT"
debug echo "########## AMBARIURL = "$AMBARIURL

currentClusterName || exit 1
debug echo "########## CLUSTER_NAME = "$CLUSTER_NAME
debug echo "########## SERVICENAME  = "$SERVICENAME
debug echo "########## ACTION = "$ACTION

if [ "$ACTION" == "start" ] ; then 
  startService $SERVICENAME || exit 1
else [ "$ACTION" == "stop" ]
  stopService $SERVICENAME || exit 1
fi
  

exit 0
