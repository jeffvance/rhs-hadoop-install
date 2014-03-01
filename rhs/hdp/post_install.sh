#!/bin/bash
#
# Copyright (c) 2013 Red Hat, Inc.
# License: Apache License v2.0
# Author: Jeff Vance <jvance@redhat.com>
#
# THIS SCRIPT IS NOT MEANT TO BE RUN STAND-ALONE. IT IS A COMPANION SCRIPT TO
# install.sh and prep_node.sh.
#
# This script does the following on each host:
#  - gets the ambari repo
#  - installs and sets up the ambari server on the mgmt node
#  - installs and sets up the ambari agent on storage node
#  - starts the ambari server and agents
#
# Arguments (all positional):
#   $1=associative array, passed by *declaration*, containing many individual
#      arg values. Note: special care needed when passing and receiving
#      associative arrays,
#
# Note on passing associative arrays: the caller needs to pass the declare -A
#   command line which initializes the array. The receiver then evals this
#   string in order to set its own assoc array.
#
# Note: the current working directory has been set by prep_node to the
#   directory where this script resides.

# constants and args
# note, delete the "declare -A name=" portion of arg
VERSION='1.01'
eval 'declare -A _ARGS='${1#*=}
STORAGE_INSTALL="${_ARGS[INST_STORAGE]}" # true or false
MGMT_INSTALL="${_ARGS[INST_MGMT]}"       # true or false
MGMT_NODE="${_ARGS[MGMT_NODE]}"          # host name
VERBOSE="${_ARGS[VERBOSE]}"  # needed by display()
LOGFILE="${_ARGS[PREP_LOG]}" # needed by display()
DEPLOY_DIR="${_ARGS[REMOTE_DIR]}"


# source common constants and functions
source ${DEPLOY_DIR}functions


# get_ambari_repo: wget the ambari repo file in the correct location.
#
function get_ambari_repo(){
 
  local REPO_DIR='/etc/yum.repos.d'
  local REPO_URL='http://public-repo-1.hortonworks.com/ambari/centos6/1.x/updates/1.4.4.23/ambari.repo'
  local out; local err

  [[ -d $REPO_DIR ]] || mkdir -p $REPO_DIR
  cd $REPO_DIR

  out="$(wget $REPO_URL 2>&1)"
  err=$?
  display "wget repo: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR $err: Ambari repo wget" $LOG_FORCE
    exit 5 
  fi
  cd - >/dev/null
}

# install_ambari_agent: yum install the ambari agent rpm, modify the .ini file
# to point to the ambari server, start the agent, and set up agent to start
# automatically after a reboot.
#
function install_ambari_agent(){

  local out; local err
  local AMBARI_INI='/etc/ambari-agent/conf/ambari-agent.ini'
  local AMBARI_AGENT_PID='/var/run/ambari-agent/ambari-agent.pid'

  echo
  display "-- Installing Ambari agent" $LOG_SUMMARY

  # stop agent if running
  if [[ -f $AMBARI_AGENT_PID ]] ; then
    display "   stopping ambari-agent" $LOG_INFO
    out="$(ambari-agent stop 2>&1)"
    err=$?
    display "ambari-agent stop: $out" $LOG_DEBUG
    (( err == 0 )) || display "WARN $err: couldn't stop ambari agent" $LOG_FORCE
  fi

  # install agent
  out="$(yum -y install ambari-agent 2>&1)"
  err=$?
  display "ambari-agent install: $out" $LOG_DEBUG
  if (( err != 0 && err != 1 )) ; then # 1--> nothing-to-do
    display "ERROR $err: ambari-agent install" $LOG_FORCE
    exit 10
  fi

  # modify the agent's .ini file to contain the mgmt node hostname
  display "  modifying $ambari_ini file" $LOG_DEBUG
  sed -i -e "s/'localhost'/${MGMT_NODE}/" $AMBARI_INI 2>&1

  # start the agent now
  out="$(ambari-agent start 2>&1)"
  err=$?
  display "ambari-agent start: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR $err: ambari-agent start" $LOG_FORCE
    exit 15
  fi

  # restart agent after reboot
  out="$(chkconfig ambari-agent on 2>&1)"
  display "ambari-agent chkconfig on: $out" $LOG_DEBUG
}

# install_ambari_server: yum install the ambari server rpm, setup start the
# server, start ambari server, and ensure the server starts after a reboot.
#
function install_ambari_server(){

  local out; local err
  local AMBARI_SERVER_PID='/var/run/ambari-server/ambari-server.pid'
  local METAINFO_PATH='/var/lib/ambari-server/resources/stacks/HDP/2.0.6.GlusterFS/metainfo.xml'
  local ACTIVE_FALSE='<active>false<'; local ACTIVE_TRUE='<active>true<'

  # stop and reset server if running
  if [[ -f $AMBARI_SERVER_PID ]] ; then
    display "   stopping ambari-server" $LOG_INFO
    out="$(ambari-server stop 2>&1)"
    err=$?
    display "ambari-server stop: $out" $LOG_DEBUG
    if (( err != 0 )) ; then
      display "WARN $err: couldn't stop ambari server" $LOG_FORCE
    fi
    out="$(ambari-server reset -s 2>&1)"
    err=$?
    display "ambari-server reset: $out" $LOG_DEBUG
    if (( err != 0 )) ; then
      display "WARN $err: couldn't reset ambari server" $LOG_FORCE
    fi
  fi

  # install the ambari server
  out="$(yum -y install ambari-server 2>&1)"
  err=$?
  display "ambari-server install: $out" $LOG_DEBUG
  if (( err != 0 && err != 1 )) ; then # 1--> nothing-to-do
    display "ERROR $err: ambari server install" $LOG_FORCE
    exit 20
  fi

  # set the active=true flag in the meta info xml file. This makes ambari
  # aware of alternative HCFS file systems, like RHS/glusterfs.
  display "   setting active flag to true" $LOG_INFO
  sed -i -e "s/$ACTIVE_FALSE/$ACTIVE_TRUE/" $METAINFO_PATH

  # setup the ambari-server
  # note: -s accepts all defaults with no prompting
  out="$(ambari-server setup -s 2>&1)"
  err=$?
  display "ambari-server setup: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR $err: ambari server setup" $LOG_FORCE
    exit 25
  fi

  # start the server now
  out="$(ambari-server start 2>&1)"
  err=$?
  display "ambari-server start: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR $err: ambari-server start" $LOG_FORCE
    exit 30
  fi

  # restart the server after a reboot
  out="$(chkconfig ambari-server on 2>&1)"
  display "ambari-server chkconfig on: $out" $LOG_DEBUG
}

# install_common: perform node installation steps independent of whether or not
# the node is to be the management server or simple a storage/data node.
#
function install_common(){

  # get ambari repo
  echo
  display "-- Getting Ambari repo file" $LOG_SUMMARY
  get_ambari_repo
}

# cleanup_logfile: if JDK was installed (and it may not be and will eventually
# be replaced by OpenJDK) then delete its progress message. When Oracle JDK
# progress is written to disk it results in a very long record in the logfile
# and the user has to forward through hundreds of "pages" to get to the next
# useful record. So, this one long record is deleted here.
#
function cleanup_logfile(){

  local DELETE_STR='jdk-' # Oracle JDK install progress pattern

  sed -i "/$DELETE_STR/d" $LOGFILE
}


# ** main ** #
#            #

echo
display "begin: HDP $(basename $0), version: $VERSION"

install_common

[[ $STORAGE_INSTALL == true ]] && install_ambari_agent
[[ $MGMT_INSTALL    == true ]] && install_ambari_server

cleanup_logfile
exit 0
#
# end of script
