#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

_DEBUG="off"

usage () {
  echo "Usage: configs.sh [-u userId] [-p password] [-port port] [-s] <ACTION> <AMBARI_HOST> <CLUSTER_NAME> <CONFIG_TYPE> [CONFIG_FILENAME | CONFIG_KEY [CONFIG_VALUE] | VOLUME_ID]";
  echo "";
  echo "       [-u userId]: Optional user ID to use for authentication. Default is 'admin'.";
  echo "       [-p password]: Optional password to use for authentication. Default is 'admin'.";
  echo "       [-port port]: Optional port number for Ambari server. Default is '8080'. Provide empty string to not use port.";
  echo "       [-s]: Optional support of SSL. Default is 'false'. Provide empty string to not use SSL.";
  echo "       <ACTION>: One of 'get', 'set', 'delete'. 'Set' adds/updates as necessary.";
  echo "       		 add_volume/remove_volume adds/removes volumes as necessary.	";
  echo "       <AMBARI_HOST>: Server external host name";
  echo "       <CLUSTER_NAME>: Name given to cluster. Ex: 'c1'"
  echo "       <CONFIG_TYPE>: One of the various configuration types in Ambari. Ex:global, core-site, hdfs-site, mapred-queue-acls, etc.";
  echo "       [CONFIG_FILENAME]: File where entire configurations are saved to, or read from. Only applicable to 'get' and 'set' actions";
  echo "       [CONFIG_KEY]: Key that has to be set or deleted. Not necessary for 'get' action.";
  echo "       [CONFIG_VALUE]: Optional value to be set. Not necessary for 'get' or 'delete' actions.";
  echo "       [VOLUME_ID]: Gluster Volume ID.";
  exit 1;
}

USERID="admin"
PASSWD="admin"
PORT=":8080"

if [ "$1" == "-u" ] ; then
  USERID=$2;
  shift 2;
  echo "USERID=$USERID";
fi

if [ "$1" == "-p" ] ; then
  PASSWD=$2;
  shift 2;
  echo "PASSWORD=$PASSWD";
fi

if [ "$1" == "-port" ] ; then
  if [ -z $2 ]; then
    PORT="";
  else
    PORT=":$2";
  fi
  shift 2;
  echo "PORT=$PORT";
fi

AMBARIURL="http://$2$PORT"
CLUSTER=$3
SITE=$4
SITETAG=''
CONFIGKEY=$5
CONFIGVALUE=$6
VOLUME_ID=$5

function DEBUG()
{
 [ "$_DEBUG" == "on" ] &&  $@
}

###################
## startService()
###################
startService () {
  DEBUG echo "########## service = "$1
  if curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER/services/$1" | grep state | cut -d : -f 2 | grep -q "STARTED" ; then
    echo "$1 already started."
  else
    echo "Starting $1 service"
    curl -u $USERID:$PASSWD -X PUT  -H "X-Requested-By: rhs" "$AMBARIURL/api/v1/clusters/$CLUSTER/services?ServiceInfo/state=INSTALLED&ServiceInfo/service_name=$1" --data "{\"RequestInfo\": {\"context\" :\"Start $1 Service\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"STARTED\"}}}";
  fi
}


###################
## stopService()
###################
stopService () {
  DEBUG echo "########## service = "$1
  if curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER/services/$1" | grep state | cut -d : -f 2 | grep -q "INSTALLED" ; then
    echo "$1 already stopped."
  else
    echo "Stopping $1 service"
    curl -u $USERID:$PASSWD -X PUT  -H "X-Requested-By: rhs" "$AMBARIURL/api/v1/clusters/$CLUSTER/services?ServiceInfo/state=STARTED&ServiceInfo/service_name=$1" --data "{\"RequestInfo\": {\"context\" :\"Start $1 Service\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"INSTALLED\"}}}";
  fi
}
###################
## currentSiteTag()
###################
currentSiteTag () {
  currentSiteTag=''
  found=''
    
  #currentSite=`cat ds.json | grep -E "$SITE|tag"`; 
  currentSite=`curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER?fields=Clusters/desired_configs" | grep -E "$SITE|tag"`;
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
    errOutput=`curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER?fields=Clusters/desired_configs"`;
    echo "[ERROR] \"$SITE\" not found in server response.";
    echo "[ERROR] Output of \`curl -s -u $USERID:$PASSWD \"$AMBARIURL/api/v1/clusters/$CLUSTER?fields=Clusters/desired_configs\"\` is:";
    echo $errOutput | while read -r line; do
      echo "[ERROR] $line";
    done;
    exit 1;
  fi
  currentSiteTag=`echo $currentSiteTag|cut -d \" -f 2`
  SITETAG=$currentSiteTag;
}

#############################################
## doConfigUpdate() 
##  @param MODE of update. Either 'set' or 'delete'
#############################################
doConfigUpdate () {
  MODE=$1
  currentSiteTag
  DEBUG echo "########## Performing '$MODE' $CONFIGKEY:$CONFIGVALUE on (Site:$SITE, Tag:$SITETAG)";
  propertiesStarted=0;
  curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER/configurations?type=$SITE&tag=$SITETAG" | while read -r line; do
    ## echo ">>> $line";
    if [ "$propertiesStarted" -eq 0 -a "`echo $line | grep "\"properties\""`" ]; then
      propertiesStarted=1
    fi;
    if [ "$propertiesStarted" -eq 1 ]; then
      if [ "$line" == "}" ]; then
        ## Properties ended
        ## Add property
        if [ "$MODE" == "set" ]; then
          newProperties="$newProperties, \"$CONFIGKEY\" : \"$CONFIGVALUE\" ";
        elif [ "$MODE" == "delete" ]; then
          # Remove the last ,
          propLen=${#newProperties}
          lastChar=${newProperties:$propLen-1:1}
          if [ "$lastChar" == "," ]; then
            newProperties=${newProperties:0:$propLen-1}
          fi
        fi
        newProperties=$newProperties$line
        propertiesStarted=0;
        
        newTag=`date "+%s"`
        newTag="version${newTag}000"
        finalJson="{ \"Clusters\": { \"desired_config\": {\"type\": \"$SITE\", \"tag\":\"$newTag\", $newProperties}}}"
        newFile="doSet_$newTag.json"
        DEBUG echo "########## PUTting json into: $newFile"
        echo $finalJson > $newFile
        curl -u $USERID:$PASSWD -X PUT -H "X-Requested-By: ambari" "$AMBARIURL/api/v1/clusters/$CLUSTER" --data @$newFile
        currentSiteTag
        DEBUG echo "########## NEW Site:$SITE, Tag:$SITETAG";
      elif [ "`echo $line | grep "\"$CONFIGKEY\""`" ]; then
        DEBUG echo "########## Config found. Skipping origin value"
      else
        newProperties=$newProperties$line
      fi
    fi
  done;
}

#############################################
## doConfigFileUpdate() 
##  @param File name to PUT on server
#############################################
doConfigFileUpdate () {
  FILENAME=$1
  if [ -f $FILENAME ]; then
    if [ "1" == "`grep -n \"\"properties\"\" $FILENAME | cut -d : -f 1`" ]; then
      newTag=`date "+%s"`
      newTag="version${newTag}000"
      newProperties=`cat $FILENAME`;
      finalJson="{ \"Clusters\": { \"desired_config\": {\"type\": \"$SITE\", \"tag\":\"$newTag\", $newProperties}}}"
      newFile="$FILENAME"
      echo $finalJson>$newFile
      DEBUG echo "########## PUTting file:\"$FILENAME\" into config(type:\"$SITE\", tag:$newTag) via $newFile"
      curl -u $USERID:$PASSWD -X PUT -H "X-Requested-By: ambari" "$AMBARIURL/api/v1/clusters/$CLUSTER" --data @$newFile
      currentSiteTag
      DEBUG echo "########## NEW Site:$SITE, Tag:$SITETAG";
    else
      DEBUG echo "[ERROR] File \"$FILENAME\" should be in the following JSON format:";
      DEBUG echo "[ERROR]   \"properties\": {";
      DEBUG echo "[ERROR]     \"key1\": \"value1\",";
      DEBUG echo "[ERROR]     \"key2\": \"value2\",";
      DEBUG echo "[ERROR]   }";
      exit 1;
    fi
  else
    echo "[ERROR] Cannot find file \"$1\"to PUT";
    exit 1;
  fi
}


#############################################
## doGet()
##  @param Optional filename to save to
#############################################
doGet () {
  FILENAME=$1
  if [ -n $FILENAME -a -f $FILENAME ]; then
    rm -f $FILENAME;
  fi
  currentSiteTag
  DEBUG echo "########## Performing 'GET' on (Site:$SITE, Tag:$SITETAG)";
  propertiesStarted=0;
  curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER/configurations?type=$SITE&tag=$SITETAG" | while read -r line; do
    ## echo ">>> $line";
    if [ "$propertiesStarted" -eq 0 -a "`echo $line | grep "\"properties\""`" ]; then
      propertiesStarted=1
    fi;
    if [ "$propertiesStarted" -eq 1 ]; then
      if [ "$line" == "}" ]; then
        ## Properties ended
        propertiesStarted=0;
      fi
      if [ -z $FILENAME ]; then
        echo $line
      else
        echo $line >> $FILENAME
      fi
    fi
  done;
}



#############################################
## doGrep() 
#############################################
doGrep () {
  currentSiteTag
  DEBUG echo "########## Performing Grep $CONFIGKEY on (Site:$SITE, Tag:$SITETAG)";
  propertiesStarted=0;
  curl -k -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER/configurations?type=$SITE&tag=$SITETAG" | while read -r line; do
    ## echo ">>> $line";
    if [ "$propertiesStarted" -eq 0 -a "`echo $line | grep "\"properties\""`" ]; then
      propertiesStarted=1
    fi;
    if [ "$propertiesStarted" -eq 1 ]; then
      if [ "$line" == "}" ]; then
        ## Properties ended
        newProperties=$newProperties$line
        propertiesStarted=0;     
      elif [ "`echo $line | grep "\"$CONFIGKEY\""`" ]; then
        DEBUG echo "########## Config found. Skipping origin value"
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

#############################################
## doUpdate() 
##  @param MODE of update. ONLY update
#############################################
doUpdate () {
  MODE=$1
  CONFIGKEY=$2
  CONFIGVALUE=$3
  currentSiteTag
  DEBUG echo "########## Performing '$MODE' $CONFIGKEY:$CONFIGVALUE on (Site:$SITE, Tag:$SITETAG)";
  propertiesStarted=0;
  curl -k -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/$CLUSTER/configurations?type=$SITE&tag=$SITETAG" | while read -r line; do
    ## echo ">>> $line";
    if [ "$propertiesStarted" -eq 0 -a "`echo $line | grep "\"properties\""`" ]; then
      propertiesStarted=1
    fi;
    if [ "$propertiesStarted" -eq 1 ]; then
      if [ "$line" == "}" ]; then
        ## Properties ended
        ## Add property
        if [ "$MODE" == "update" ]; then
          newProperties="$newProperties, \"$CONFIGKEY\" : \"$CONFIGVALUE\" ";
        fi
        if [ "$MODE" == "remove" ]; then
          newProperties="$newProperties, \"$CONFIGKEY\" : \"$CONFIGVALUE\" ";
        fi
        newProperties=$newProperties$line
        propertiesStarted=0;
        
        newTag=`date "+%s"`
        newTag="version${newTag}001"
        finalJson="{ \"Clusters\": { \"desired_config\": {\"type\": \"$SITE\", \"tag\":\"$newTag\", $newProperties}}}"
        newFile="doUpdate_$newTag.json"
        DEBUG echo "########## PUTting json into: $newFile"
        echo $finalJson > $newFile
        curl -k -u $USERID:$PASSWD -X PUT -H "X-Requested-By: ambari" "$AMBARIURL/api/v1/clusters/$CLUSTER" --data @$newFile
        currentSiteTag
        DEBUG echo "########## NEW Site:$SITE, Tag:$SITETAG";
      elif [ "`echo $line | grep "\"$CONFIGKEY\""`" ]; then
        DEBUG echo "########## Config found. Skipping origin value"
        line1=$line
        propLen=${#line1}
        lastChar=${line1:$propLen-1:1}
        if [ "$lastChar" == "," ]; then
          line1=${line1:0:$propLen-1}
        fi
	DEBUG echo "########## LINE = "$line1
	OIFS="$IFS"
	IFS=':'
	read -a keyvalue <<< "${line1}"
	IFS="$OIFS"
	key=${keyvalue[0]}
	value=${keyvalue[1]}
	value=`echo $value | sed "s/\"//g"`
	DEBUG echo "########## VALUE = "$value
	STR_ARRAY=(`echo $value | tr "," "\n"`)
	for x in ${STR_ARRAY[@]}
	do
		#echo "&gt; [$x]"
		if ([ $x != $CONFIGVALUE ])
		then
		    #DEBUG echo "$x"
		    NEW_STR_ARRAY=( "${NEW_STR_ARRAY[@]}" "$x" )
		fi
	done
	A=${STR_ARRAY[@]};
	B=${NEW_STR_ARRAY[@]};
	DEBUG echo "########## A = ["${#STR_ARRAY[@]}"] B = ["${#NEW_STR_ARRAY[@]}"]"
        if [ "$MODE" == "update" ]; then
		#check if key is already present
		if [ "$A" != "$B" ]
		then
		  DEBUG echo "ERROR!! Volume $CONFIGVALUE aready present in $key."
		   CONFIGVALUE=$value
		else
		  if [ ${#STR_ARRAY[@]} -eq 0 ]; then
		      CONFIGVALUE=$CONFIGVALUE
		  else
		      CONFIGVALUE=$value","$CONFIGVALUE
		  fi
	        fi
		DEBUG echo "########## CONFIGVALUE = "$CONFIGVALUE	
	else
		NEW_STR_ARRAY_COMMA=""
		for x in ${NEW_STR_ARRAY[@]}
		do
		  NEW_STR_ARRAY_COMMA+=$x","
		done
		line1=$NEW_STR_ARRAY_COMMA
		propLen=${#line1}
		lastChar=${line1:$propLen-1:1}
		if [ "$lastChar" == "," ]; then
		  line1=${line1:0:$propLen-1}
		fi
		CONFIGVALUE=$line1
		DEBUG echo "########## CONFIGVALUE = "$CONFIGVALUE	
	fi
      else
        newProperties=$newProperties$line
      fi
    fi
  done;
}


case "$1" in
  set)
    if (($# == 6)); then
      doConfigUpdate "set" # Individual key
    elif (($# == 5)); then
      doConfigFileUpdate $5 # File based
    else
      usage
    fi
    ;;
  add_volume)
    if (($# == 5)); then
      doUpdate "update" "fs.glusterfs.volumes" $5 # Individual key
      sleep 4	
      CONFIGKEY="fs.glusterfs.volume.fuse."$5
      CONFIGVALUE="/mnt/"$5	
      doConfigUpdate "set"
    else
      usage
    fi
    ;;
  remove_volume)
    if (($# == 5)); then
      doUpdate "remove" "fs.glusterfs.volumes" $5 # Individual key
      sleep 4
      CONFIGKEY="fs.glusterfs.volume.fuse."$5
      CONFIGVALUE="/mnt/"$5
      doConfigUpdate "delete"
    else
      usage
    fi
    ;;
  grep)
    if (($# == 5)); then
      doGrep $5
    else
      usage
    fi
    ;;
  get)
    if (($# == 4)); then
      doGet
    elif (($# == 5)); then
      doGet $5
    else
      usage
    fi
    ;;
  delete)
    if (($# != 5)); then
      usage
    fi
    doConfigUpdate "delete"
    ;;
  *) 
    usage
    ;;
esac
