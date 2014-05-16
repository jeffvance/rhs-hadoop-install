#!/bin/bash
#
# ambari_config_grep.sh searches for core-site config property or property value
#
# Syntax: see usage() function.

_DEBUG="off"
USERID="admin"
PASSWD="admin"
PORT=":8080"
PARAMS=''
AMBARI_HOST='localhost'
PROPERTY=''
CLUSTER_NAME=""
SITE="core-site"
SITETAG=''

# debug: execute cmd in $1 if _DEBUG is set to 'on'.
# Uses globals:
#   _DEBUG
function debug()
{
 [ "$_DEBUG" == "on" ] &&  $@
}

# usage: echos general usage paragraph.
function usage () {
  echo "Usage: ambari_config_grep.sh [-u userId] [-p password] [--port port] [-h ambari_host] [--config config-site] <PROPERTY>"
  echo ""
  echo "       [-u userId]: Optional user ID to use for authentication. Default is 'admin'."
  echo "       [-p password]: Optional password to use for authentication. Default is 'admin'."
  echo "       [--port port]: Optional port number for Ambari server. Default is '8080'. Provide empty string to not use port."
  echo "       [-h ambari_host]: Optional external host name for Ambari server. Default is 'localhost'."
  echo "       [--config config-site]: core-site | mapred-site | yarn site .default cofig file is core-site."
  echo "       [PROPERTY]: config property or property value."
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
#   PROPERTY
function parse_cmd(){

  local OPTIONS='u:p:h:'
  local LONG_OPTS='port:,config:,help,debug'

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
      --config)
        [[ -n "$2" ]] && SITE="$2"
        debug echo "SITE=$SITE"
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
    echo "Syntax error: [PROPERTY] is missing"; usage ; return 1
  fi
  #make sure there is only one property
  if (( $# > 1 )); then
    echo "Syntax error: Unknown values: \"$@\""; return 1
  fi

  if [[ -z "$1" ]]; then
    echo "Syntax error: PROPERTY is missing: \"$@\""; usage ; return 1
  else
    PROPERTY="$1"
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


# currentSiteTag: sets the SITETAG based on the value in the ambari
# config file. Returns 1 on errors.
# Set globals:
#   SITETAG
currentSiteTag () {
  local currentSiteTag=''
  local found=''
  local line ; local errOutput ;
    
  currentSite=$(curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME?fields=Clusters/desired_configs" | grep -E "$SITE|tag")
  for line in $currentSite; do
    if [ $line != "{" -a $line != ":" -a $line != '"tag"' ] ; then
      if [ -n "$found" -a -z "$currentSiteTag" ]; then
        currentSiteTag=$line;
      fi
      if [ $line == "\"$SITE\"" ]; then
        found=$SITE; 
      fi
    fi
  done;
  if [ -z $currentSiteTag ]; then
    errOutput=$(curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME?fields=Clusters/desired_configs")
    echo "[ERROR] \"$SITE\" not found in server response.";
    echo "[ERROR] Output of \`curl -s -u $USERID:$PASSWD \"$AMBARIURL/api/v1/clusters/$CLUSTER_NAME?fields=Clusters/desired_configs\"\` is:";
    echo $errOutput | while read -r line; do
      echo "[ERROR] $line";
    done;
    return 1;
  fi
  currentSiteTag=$(echo $currentSiteTag|cut -d \" -f 2)
  SITETAG="$currentSiteTag" 
}


# doGrep: searches the core-site for all key:value having Property
# input $1 : property
# Return 1 if config cannot be found in Ambari
doGrep () {
  currentSiteTag
  local property="$1"
  local propertiesStarted=0;
  local line ; local line1 ; local lastChar
  local newProperties ;local found ;local config_json 

  debug echo "########## Performing Grep ["$property"] on (Site:$SITE, Tag:$SITETAG)";
 
  config_json=$(curl -k -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME/configurations?type=$SITE&tag=$SITETAG");
  check_error=$(echo $config_json | grep "\"status\"")
  if [ "$check_error" ]; then
    echo "[ERROR] \"$SITE\" not found in server response.";
    return 1 
  fi

  echo "$config_json" | while read -r line; do
    #echo ">>> $line";
    if [ "$propertiesStarted" -eq 0 -a "`echo $line | grep "\"properties\""`" ]; then
      propertiesStarted=1
    fi;
    if [ "$propertiesStarted" -eq 1 ]; then
      if [ "$line" == "}" ]; then
        ## Properties ended
        newProperties=$newProperties$line
        propertiesStarted=0;     
      elif [ "`echo $line | grep "\"$property\""`" ]; then
        debug echo "########## Config found. Skipping origin value"
        line1=$line
        propLen=${#line1}
        lastChar=${line1:$propLen-1:1}
        if [ "$lastChar" == "," ]; then
          line1=${line1:0:$propLen-1}
        fi
        echo $line1
      else
        newProperties=$newProperties$line
      fi
    fi
  done;
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

doGrep "$PROPERTY" || exit 1

exit 0
