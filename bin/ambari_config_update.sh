#!/bin/bash
#
# ambari_config_update.sh add/remove value in a property
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
CONFIG_KEY=''
CONFIG_VALUE=''
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
  echo "Usage: ambari_config_update.sh [-u userId] [-p password] [--port port] [-h ambari_host] [--config config-site] --action add|remove  --configkey CONFIG_KEY --configvalue CONFIG_VALUE"
  echo ""
  echo "       [-u userId]: Optional user ID to use for authentication. Default is 'admin'."
  echo "       [-p password]: Optional password to use for authentication. Default is 'admin'."
  echo "       [--port port]: Optional port number for Ambari server. Default is '8080'. Provide empty string to not use port."
  echo "       [-h ambari_host]: Optional external host name for Ambari server. Default is 'localhost'."
  echo "       [--config config-site]: core-site | mapred-site | yarn site .default config file is core-site."
  echo "       --action add|remove : add/remove CONFIG_VALUE"
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
function parse_cmd(){

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

  
  #take care of all other arguments
  if [[ -z "$ACTION" ]]; then
    echo "Syntax error: ACTION is missing"; usage ; return 1
  fi
  if [[ -z "$CONFIG_VALUE" ]]; then
    echo "Syntax error: CONFIG_VALUE is missing"; usage ; return 1
  fi
  if [[ -z "$CONFIG_KEY" ]]; then
    echo "Syntax error: CONFIG_KEY is missing"; usage ; return 1
  fi

  ACTION=$(echo "$ACTION" | sed "s/[\"\,\ ]//g")
  if [ "$ACTION" == "add" ] || [ "$ACTION" == "remove" ]; then
   ACTION=$ACTION
  else
    echo "Syntax error: ACTION should be add|remove"; usage ; return 1
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


# doUpdate: UPDATES the PROPERTY IN SITETAG
# Returns 1 on errors.
# Input : $1 mode ;$2 key ;$3 value
doUpdate () {
  local mode=$1
  local configkey=$2
  local configvalue=$3
  local currentSiteTag=''
  local found=''
  local line ; local line1 ; local propertiesStarted ; local newProperties; local errOutput ;
  local newTag ; local finalJson ;local newFile
  local keyvalue=() ;local old=() ;local new=()

  currentSiteTag
  debug echo "########## Performing '$mode' $configkey:$configvalue on (Site:$SITE, Tag:$SITETAG)";
  propertiesStarted=0;
  curl -k -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME/configurations?type=$SITE&tag=$SITETAG" | while read -r line; do
    ## echo ">>> $line";
    if [ "$propertiesStarted" -eq 0 -a "`echo $line | grep "\"properties\""`" ]; then
      propertiesStarted=1
    fi;
    if [ "$propertiesStarted" -eq 1 ]; then
      if [ "$line" == "}" ]; then
        ## Properties ended
        ## Add property
        [ "$mode" == "add" -o "$mode" == "remove" ] && newProperties="$newProperties, \"$configkey\" : \"$configvalue\" ";

        newProperties=$newProperties$line
        propertiesStarted=0;
        
        newTag=$(date "+%s")
        newTag="version${newTag}001"
        finalJson="{ \"Clusters\": { \"desired_config\": {\"type\": \"$SITE\", \"tag\":\"$newTag\", $newProperties}}}"
        newFile="doUpdate_$newTag.json"
        debug echo "########## PUTting json into: $newFile"
        echo $finalJson > $newFile
        
        check_error="$(eval "curl -k -s -u $USERID:$PASSWD -X PUT -H "X-Requested-By:ambari" "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME" --data @$newFile ")"
        err=$?
        if (( err != 0 )) ; then
          echo "[ERROR] $check_error.";
          return 1
        fi
        check_error=$(echo $check_error | grep "\"status\"")
        if [ "$check_error" ]; then
          echo "[ERROR] $check_error.";
          return 1 
        fi

        sleep 4
        echo  "changed $configkey. New value is [$configvalue]."
        currentSiteTag
        debug echo "########## NEW Site:$SITE, Tag:$SITETAG";
      elif [ "`echo $line | grep "\"$configkey\""`" ]; then
        debug echo "########## Config found. Skipping origin value"
        
        #remove comma
        line1=$line
        propLen=${#line1}
        lastChar=${line1:$propLen-1:1}
        if [ "$lastChar" == "," ]; then
          line1=${line1:0:$propLen-1}
        fi
        debug echo "########## LINE = "$line1
        
        
        OIFS="$IFS"
        IFS=':'
        read -a keyvalue <<< "${line1}"
        IFS="$OIFS"
        key=${keyvalue[0]}
        value=${keyvalue[1]}
        value=$(echo "$value" | sed "s/[\"\ ]//g")
        debug echo "########## current VALUE = "$value
        
        
        STR_ARRAY=(`echo $value | tr "," "\n"`)
        for x in ${STR_ARRAY[@]}
        do
          if ([ $x != $configvalue ])
            then
              NEW_STR_ARRAY=( "${NEW_STR_ARRAY[@]}" "$x" ) 
          fi
        done
        old=${STR_ARRAY[@]};
        new=${NEW_STR_ARRAY[@]};
        debug echo "########## old = ["${#STR_ARRAY[@]}"] new = ["${#NEW_STR_ARRAY[@]}"]"
        
        if [ "$mode" == "add" ]; then
          #check if key is already present
          if [ "$old" != "$new" ] ; then
            echo "ERROR!! $configvalue aready present in $configkey."
            #configvalue=$value
            return 1 
          else
            if [ ${#STR_ARRAY[@]} -eq 0 ]; then
              configvalue=$configvalue
            else
              configvalue=$value","$configvalue
            fi
          fi
          debug echo "########## add configvalue = "$configvalue  
        else
          #check if key is already present
          if [ "$old" == "$new" ] ; then
            echo "ERROR!! $configvalue not present in $configkey."
            #configvalue=$value
            return 1 
          fi
          NEW_STR_ARRAY_COMMA=""
          for x in ${NEW_STR_ARRAY[@]}
          do
            NEW_STR_ARRAY_COMMA+=$x","
          done

          #remove comma
          line1=$NEW_STR_ARRAY_COMMA
          propLen=${#line1}
          lastChar=${line1:$propLen-1:1}
          if [ "$lastChar" == "," ]; then
            line1=${line1:0:$propLen-1}
          fi
          configvalue=$line1
          debug echo "########## remove configvalue = "$configvalue  
        fi
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
debug echo "########## "$ACTION $CONFIG_KEY $CONFIG_VALUE

doUpdate $ACTION $CONFIG_KEY $CONFIG_VALUE || exit 1

exit 0
