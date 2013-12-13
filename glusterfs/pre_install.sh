#!/bin/bash
#
# Copyright (c) 2013 Red Hat, Inc.
# License: Apache License v2.0
# Author: Jeff Vance <jvance@redhat.com>
#
# Please read the README file.
#
# THIS SCRIPT IS NOT MEANT TO BE RUN STAND-ALONE. It is automatically executed
# as an initial step by ../prep_node.sh.
#
# This script does the following on the host (this) node:
#  - install xfs if needed
#  - install or update glusterfs if needed
#
# Arguments (all positional):
#   $1=self hostname*, $2=install storage flag*, $3=install mgmt server flag*,
#   $4=HOSTS(array)*, $5=HOST IP-addrs(array)*, $6=management server hostname*,
#   $7=verbose value*, $8=special logfile*, $9=working dir, $10=rhn user,
#   $11=rhn user password
# '*' means required argument, others are optional.
#
# constants and args
NODE=$1
STORAGE_INSTALL=$2 # true or false
MGMT_INSTALL=$3    # true or false
HOSTS=($4)
HOST_IPS=($5)
MGMT_NODE="$6" # note: this node can be inside or outside the storage cluster
VERBOSE=$7
LOGFILE=$8
DEPLOY_DIR=${9:-/tmp/rhs-hadoop-install/}
RHN_USER=${10:-}
RHN_PASS=${11:-}
#echo -e "*** $(basename $0)\n 1=$NODE, 2=$STORAGE_INSTALL, 3=$MGMT_INSTALL, 4=${HOSTS[@]}, 5=${HOST_IPS[@]}, 6=$MGMT_NODE, 7=$VERBOSE, 8=$LOGFILE, 9=$DEPLOY_DIR, 10=$RHN_USER, 11=$RHN_PASS"

NUMNODES=${#HOSTS[@]}

# source common constants and functions
source ${DEPLOY_DIR}functions


# get_plugin: wget the most recent gluster-hadoop plug-in from archiva or
# s3 (moving off of archiva soon) and copy it to PWD. This is done by scraping
# the main gluster-hadoop index page and getting the last href for the jar URL.
#
function get_plugin(){

  local HTTP='http://23.23.239.119'
  local INDEX_URL="$HTTP/archiva/browse/org.apache.hadoop.fs.glusterfs/glusterfs-hadoop" # note: will change when move to s3
  local JAR_URL="$HTTP/archiva/repository/internal/org/apache/hadoop/fs/glusterfs/glusterfs-hadoop"
  local JAR_SEARCH='<li><a href=\"/archiva/browse/org.apache.hadoop.fs.glusterfs'
  local SCRAPE_FILE='plugin-index.txt'
  local jar=''; local jar_ver; local out

  display "-- Getting glusterfs-hadoop plugin"... $LOG_SUMMARY
  # get plugin index page and find the most current version, which is the last
  # list element (<li><a href=...) on the index page
  wget -q -O $SCRAPE_FILE $INDEX_URL
  jar_ver=$(grep "$JAR_SEARCH" $SCRAPE_FILE | tail -n 1)
  jar_ver=${jar_ver%;*}        # delete trailing ';jsessionid...</a></li>'
  jar_ver=${jar_ver##*hadoop/} # delete from beginning to last "hadoop/"
  # now jar_ver contains the most recent plugin jar version string
  wget $JAR_URL/$jar_ver/glusterfs-hadoop-$jar_ver.jar

  jar=$(ls glusterfs-hadoop*.jar 2> /dev/null)
  if [[ -z "$jar" ]] ; then
    display "ERROR: gluster-hadoop plug-in missing in $DEPLOY_DIR" $LOG_FORCE
    display "       attemped to retrieve JAR from $INDEX_URL/$jar_ver/" \
        $LOG_FORCE
    exit 3
  fi
  display "   glusterfs-hadoop plugin copied to $PWD" $LOG_SUMMARY
}

# install_storage: perform the installation steps needed when the node is a
# storage/data node.
#
function install_storage(){

  get_plugin
}

# install_mgmt: perform the installations steps needed when the node is the
# management node.
#
function install_mgmt(){

  # nothing to do here (yet)...
}


# ** main ** #
#            #
echo
display "$(date). Begin: $0" $LOG_REPORT

[[ $STORAGE_INSTALL == true ]] && install_storage
[[ $MGMT_INSTALL    == true ]] && install_mgmt

echo
display "$(date). End: $0" $LOG_REPORT
 
# end of script

