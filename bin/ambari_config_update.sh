#!/bin/bash
#
# ambari_config_update.sh add/remove value in a property
#
# Syntax: see usage() function.

PREFIX="$(dirname $(readlink -f $0))"

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
CONFIG_KEY=''
CONFIG_VALUE=''
ACTION=""

## functions ##

source $PREFIX/functions

# debug: execute cmd in $1 if _DEBUG is set to 'on'.
# Uses globals:
#   _DEBUG
function debug() {
 [ "$_DEBUG" == "on" ] &&  $@
}

# usage: echos general usage paragraph.
function usage() {
  echo "Usage: ambari_config_update.sh [-u userId] [-p password] [--port port] [-h ambari_host] [--config config-site] --action add|remove  --configkey CONFIG_KEY --configvalue CONFIG_VALUE"
  echo ""
  echo "       [-u userId]: Optional user ID to use for authentication. Default is 'admin'."
  echo "       [-p password]: Optional password to use for authentication. Default is 'admin'."
  echo "       [--port port]: Optional port number for Ambari server. Default is '8080'. Provide empty string to not use port."
  echo "       [-h ambari_host]: Optional external host name for Ambari server. Default is 'localhost'."
  echo "       [--config config-site]: core-site | mapred-site | yarn site .default config file is core-site."
  echo "       --action prepend|append|remove: add/remove CONFIG_VALUE"
  echo "       --configkey CONFIG_KEY : property Key in config-site."
  echo "       --configvalue CONFIG_VALUE: property value to be appended with comma."
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
#   CONFIG_KEY 
#   CONFIG_VALUE
function parse_cmd() {

  local OPTIONS='u:p:h:'
  local LONG_OPTS='port:,action:,configkey:,configvalue:,config:,help,debug'

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
      --action)
        [[ -n "$2" ]] && ACTION="$2"
        debug echo "ACTION=$ACTION"
        shift 2; continue
       ;;
      --configkey)
        [[ -n "$2" ]] && CONFIG_KEY="$2"
        debug echo "CONFIG_KEY=$CONFIG_KEY"
        shift 2; continue
       ;;
      --configvalue)
        [[ -n "$2" ]] && CONFIG_VALUE="$2"
        debug echo "CONFIG_VALUE=$CONFIG_VALUE"
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

  
  # take care of all other arguments
  [[ -z "$ACTION" ]] && {
    echo "Syntax error: ACTION is missing"; usage ; return 1; }
  [[ "$ACTION" != "prepend" && "$ACTION" != "append" && "$ACTION" != "remove" ]] && {
    echo "Syntax error: ACTION is expected to be  one of: prepend|append|remove";
    usage ; return 1; }

  [[ -z "$CONFIG_VALUE" ]] && {
    echo "Syntax error: CONFIG_VALUE is missing"; usage ; return 1; }

  [[ -z "$CONFIG_KEY" ]] && {
    echo "Syntax error: CONFIG_KEY is missing"; usage ; return 1; }

  eval set -- "$@" # move arg pointer so $1 points to next arg past last opt

  [[ $DEBUG == true ]] && debug echo "DEBUGGING ON"
  return 0
}

# currentSiteTag: sets the SITETAG based on the value in the ambari
# config file. Returns 1 on errors.
# Set globals:
#   SITETAG
function currentSiteTag() {

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
  done

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


# doUpdate: updates the PROPERTY in SITETAG. Returns 1 on errors. Returns 0 for no
# errors or for warnings.
# Input : $1 mode; $2 key; $3 value
function doUpdate() {

  local mode=$1; local configkey=$2; local configvalue=$3
  local tmp_cfg="$(mktemp --suffix .$SITE)"
  local old_value; local new_value; local newTag
  local line; local out; local err
  local json_begin="{ \"Clusters\": { \"desired_config\": {\"type\": \"$SITE\", "
  local json_end='}}}'

  currentSiteTag
  debug echo "########## Performing '$mode' $configkey:$configvalue on (Site:$SITE, Tag:$SITETAG)";

  # extract the properties section and write to tmp config file
  curl -k -s -u $USERID:$PASSWD \
   "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME/configurations?type=$SITE&tag=$SITETAG"\
  | sed -n '/\"properties\" :/,/}$/p' >$tmp_cfg # just the "properties" section

  # extract the target key line
  line="$(grep "\"$configkey\"" $tmp_cfg)"
  line="${line%,}" # remove trailing comma if present
  debug echo "########## LINE = $line"

  # extract the unquoted value from line
  old_value="${line#*: }"       # just value portion
  old_value="${old_value//\"/}" # remove all double-quotes
  debug echo "########## current VALUE = $old_value"

  if [[ "$mode" == 'append' || "$mode" == 'prepend' ]] ; then
    # check if key is already present
    if [[ ",$old_value," =~ ",$configvalue," ]] ; then
      echo "WARN: $configvalue already present in $configkey; no action needed"
      return 0
    fi
    if [[ "$mode" == 'prepend' ]] ; then
      new_value="$configvalue,$old_value"
    else # append
      new_value="$old_value,$configvalue"
    fi
    debug echo "########## new configvalue = $new_value"

  else # mode(action) = remove
    # check if configvalue exists
    if [[ ! ",$old_value," =~ ",$configvalue," ]] ; then
      echo "WARN: $configvalue not present in $configkey; no action needed"
      return 0 
    fi
    new_value="${old_value/$configvalue/}" # remove configvalue
    new_value="${new_value#,}"    # remove leading comma, if any
    new_value="${new_value%,}"    # remove trailing comma, if any
    new_value="${new_value/,,/,}" # fold double commas to single, if any
    debug echo "########## remove configvalue = $new_value"
  fi

  # done constructing new property value
  # fix up the "property" section for the PUT below:
  # update new configvalue in place
  sed -i "/$configkey/s/$old_value/$new_value/" $tmp_cfg
  # prepend and append "desired_config" json to config file
  newTag="version$(date '+%s')001"
  json_begin+="\"tag\":\"$newTag\", "
  sed -i "1i $json_begin" $tmp_cfg # prepend json to config file
  echo "$json_end" >>$tmp_cfg
  debug echo "########## new property:"
  debug echo "$(cat $tmp_cfg)"

  # PUT/update the real config(core) file
  out="$(curl -k -s -u $USERID:$PASSWD -X PUT -H 'X-Requested-By:ambari' \
	 $AMBARIURL/api/v1/clusters/$CLUSTER_NAME --data @$tmp_cfg)"
  err=$?
  if (( err != 0 )) || grep -q '"status"' <<<$out ; then
    echo "ERROR: $out"
    return 1
  fi
  sleep 4

  return 0
}

## ** main ** ##

# defaults (global variables)
DEBUG=false
SCRIPT=$0

parse_cmd $@ || exit -1

AMBARIURL="http://$AMBARI_HOST$PORT"
debug echo "########## AMBARIURL = "$AMBARIURL

CLUSTER_NAME="$(currentClusterName $AMBARIURL "$USERID" "$PASSWD")" || {
  echo "$CLUSTER_NAME"; # contains error msg
  exit 1; }
debug echo "########## CLUSTER_NAME = $CLUSTER_NAME"
debug echo "########## $ACTION $CONFIG_KEY $CONFIG_VALUE"

doUpdate $ACTION $CONFIG_KEY $CONFIG_VALUE || exit 1

exit 0
