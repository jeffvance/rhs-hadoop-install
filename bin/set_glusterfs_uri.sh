#!/bin/bash

_DEBUG="off"
CLUSTER=$3
SITE=$4
SITETAG=''
CONFIGKEY=$5
CONFIGVALUE=$6
VOLUME_ID=$5
CLUSTER_NAME=""


usage () {
  echo "Usage: set_glusterfs_uri.sh [-u userId] [-p password] [-port port] <AMBARI_HOST> <VOLUME_ID>";
  echo "";
  echo "       [-u userId]: Optional user ID to use for authentication. Default is 'admin'.";
  echo "       [-p password]: Optional password to use for authentication. Default is 'admin'.";
  echo "       [-port port]: Optional port number for Ambari server. Default is '8080'. Provide empty string to not use port.";
  echo "       [-h ambari_host]: Optional external host name for Ambari server. Default is 'localhost'.";
  echo "       [VOLUME_ID]: Gluster Volume ID.";
  exit 1;
}

USERID="admin"
PASSWD="admin"
PORT=":8080"
PARAMS=''
AMBARI_HOST='localhost'
CLUSTER_NAME=""


if [ "$1" == "-u" ] ; then
  USERID=$2;
  shift 2;
  echo "USERID=$USERID";
  PARAMS="-u $USERID "
fi

if [ "$1" == "-p" ] ; then
  PASSWD=$2;
  shift 2;
  echo "PASSWORD=$PASSWD";
  PARAMS=$PARAMS" -p $PASSWD "
fi

if [ "$1" == "-port" ] ; then
  if [ -z $2 ]; then
    PORT="";
  else
    PORT=":$2";
  fi
  echo "PORT=$2";
  PARAMS=$PARAMS" -port $2 "
  shift 2;
fi

if [ "$1" == "-h" ] ; then
  if [ -z $2 ]; then
    AMBARI_HOST=$AMBARI_HOST;
  else
    AMBARI_HOST="$2";
  fi
  echo "AMBARI_HOST=$2";
  shift 2;
fi

AMBARIURL="http://$AMBARI_HOST$PORT"



function DEBUG()
{
 [ "$_DEBUG" == "on" ] &&  $@
}

########################
## currentClusterName()
########################
currentClusterName () {

  line=`curl -s -u $USERID:$PASSWD "$AMBARIURL/api/v1/clusters/" | grep -E "cluster_name" | sed "s/\"//g"`;
  if [ -z "$line" ]; then
    echo "[ERROR] not Cluster was found in server response.";
    exit 1;
  fi

  DEBUG echo "########## LINE = "$line

  line1=$line
  propLen=${#line1}
  lastChar=${line1:$propLen-1:1}
  if [ "$lastChar" == "," ]; then
    line1=${line1:0:$propLen-1}
  fi

  OIFS="$IFS"
  IFS=':'
  read -a keyvalue <<< "${line1}"
  IFS="$OIFS"
  key=${keyvalue[0]}
  value="${keyvalue[1]}"

  value=`echo $value | sed "s/\"//g"`
  DEBUG echo "########## VALUE = "$value
  CLUSTER_NAME="$value" 
}

	
currentClusterName
DEBUG echo "########## CLUSTER_NAME = "$CLUSTER_NAME
PARAMS=$PARAMS" add_volume $AMBARI_HOST $CLUSTER_NAME core-site "
PARAMS=`echo $PARAMS | sed "s/\"//g"`
DEBUG echo "########## PARAMS = "$PARAMS	

if (($# == 1)); then
  DEBUG "sh ./ambari_config.sh $PARAMS $1"
  sh ./ambari_config.sh $PARAMS $1	
else
  usage
fi

