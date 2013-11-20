#!/bin/bash
#
# Copyright (c) 2013 Red Hat, Inc.
# License: Apache License v2.0
# Author: Jeff Vance <jvance@redhat.com>
#
# THIS SCRIPT IS NOT MEANT TO BE RUN STAND-ALONE. IT IS A COMPANION SCRIPT TO
# install.sh and prep_node.sh.
#
# This script is executed by prep_node.sh. It is passed the same args as passed
# to prep_node. This script installs the Ambari server and/or agent RPMs, starts
# Ambari, and configures Ambari to start on reboot. Ambari dependencies are also
# installed.
#
# Arguments (all positional):
#   same as passed to prep_node.sh.

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

AMBARI_TMPDIR=${DEPLOY_DIR}tmpAmbari
AMBARI_TARBALL_GLOB='ambari-*.tar.gz'

# source common constants and functions
. ${DEPLOY_DIR}functions


# copy_ambari_repo: copy the ambari.repo file to the correct location.
#
function copy_ambari_repo(){
 
  local REPO='ambari.repo'; local REPO_DIR='/etc/yum.repos.d'
  local out; local err

  if [[ ! -f $REPO ]] ; then
    display "ERROR: \"$REPO\" file missing" $LOG_FORCE
    exit 3
  fi
  [[ -d $REPO_DIR ]] || mkdir -p $REPO_DIR

  out="$(cp $REPO $REPO_DIR 2>&1)"
  err=$?
  display "ambari repo cp: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: ambari repo copy $err" $LOG_FORCE
    exit 5 
  fi
}

# install_epel: install the epel rpm. Note: epel package is not part of the
# install tarball and therefore must be installed over the internet via the
# ambari repo file. It is required that the ambari.repo file has been copied 
# to the correct dir prior to invoking this function.
#
function install_epel(){

  local out; local err
 
  out="$(yum -y install epel-release 2>&1)"
  err=$?
  display "install epel: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: yum install epel-release error $err" $LOG_FORCE
    exit 7
  fi
}

# install_ambari_agent: untar the ambari rpm tarball, yum install the ambari
# agent rpm, modify the .ini file to point to the ambari server, start the
# agent, and set up agent to start automatically after a reboot.
#
function install_ambari_agent(){

  local agent_rpm=''; local out; local err
  local AMBARI_AGENT_GLOB='ambari-agent-*.rpm'
  local ambari_ini='/etc/ambari-agent/conf/ambari-agent.ini'
  local SERVER_SECTION='server'; SERVER_KEY='hostname='
  local KEY_VALUE="$MGMT_NODE"
  local AMBARI_AGENT_PID='/var/run/ambari-agent/ambari-agent.pid'

  echo
  display "-- Installing Ambari agent" $LOG_SUMMARY

  ls $AMBARI_TARBALL_GLOB >& /dev/null || {
	display "ERROR: ambari tarball missing in $PWD" $LOG_FORCE;
	exit 9; }
 
  mkdir -p $AMBARI_TMPDIR

  # extract ambari rpms, if not present
  if ! ls $AMBARI_TMPDIR/$AMBARI_AGENT_GLOB >& /dev/null ; then 
    out="$(tar -C $AMBARI_TMPDIR -xzf $AMBARI_TARBALL_GLOB 2>&1)"
    err=$?
    display "untar ambari RPMs: $out" $LOG_DEBUG
    if (( err != 0 )) ; then
      display "ERROR: untar ambari RPMs: $err" $LOG_FORCE
      exit 11
    fi
  fi

  cd $AMBARI_TMPDIR

  # stop agent if running
  if [[ -f $AMBARI_AGENT_PID ]] ; then
    display "   stopping ambari-agent" $LOG_INFO
    out="$(ambari-agent stop 2>&1)"
    err=$?
    display "ambari-agent stop: $out" $LOG_DEBUG
    (( err == 0 )) || display "WARN: couldn't stop ambari agent" $LOG_FORCE
  fi

  # install agent rpm
  agent_rpm="$(ls $AMBARI_AGENT_GLOB 2>/dev/null)"
  if [[ -z "$agent_rpm" ]] ; then
    display "ERROR: Ambari agent RPM missing" $LOG_FORCE
    exit 13
  fi
  out="$(yum -y install $agent_rpm 2>&1)"
  err=$?
  display "ambari-agent install: $out" $LOG_DEBUG
  if (( err != 0 && err != 1 )) ; then # 1--> nothing-to-do
    display "ERROR: ambari-agent install error $err" $LOG_FORCE
    exit 16
  fi

  cd -

  # modify the agent's .ini file's server hostname value
  display "  modifying $ambari_ini file" $LOG_DEBUG
  sed -i -e "/\[${SERVER_SECTION}\]/,/${SERVER_KEY}/s/=.*$/=${KEY_VALUE}/" $ambari_ini

  # start the agent
  out="$(ambari-agent start 2>&1)"
  err=$?
  display "ambari-agent start: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: ambari-agent start error $err" $LOG_FORCE
    exit 19
  fi

  # start agent after reboot
  out="$(chkconfig ambari-agent on 2>&1)"
  display "ambari-agent chkconfig on: $out" $LOG_DEBUG
}

# install_ambari_server: yum install the ambari server rpm, setup start the
# server, start ambari server, and start the server after a reboot.
#
function install_ambari_server(){

  local server_rpm=''; local out; local err
  local AMBARI_SERVER_GLOB='ambari-server-*.rpm'
  local AMBARI_SERVER_PID='/var/run/ambari-server/ambari-server.pid'

  ls $AMBARI_TARBALL_GLOB >& /dev/null || {
	display "ERROR: ambari tarball missing in $PWD" $LOG_FORCE;
	exit 22; }

  mkdir -p $AMBARI_TMPDIR
 
  # extract ambari rpms if not present
  if ! ls $AMBARI_TMPDIR/$AMBARI_SERVER_GLOB >& /dev/null ; then
    out="$(tar -C $AMBARI_TMPDIR -xzf $AMBARI_TARBALL_GLOB 2>&1)"
    err=$?
    display "untar ambari RPMs: $out" $LOG_DEBUG
    if (( err != 0 )) ; then
      display "ERROR: untar ambari RPMs error: $err" $LOG_FORCE
      exit 25
    fi
  fi

  cd $AMBARI_TMPDIR

  # stop and reset server if running
  if [[ -f $AMBARI_SERVER_PID ]] ; then
    display "   stopping ambari-server" $LOG_INFO
    out="$(ambari-server stop 2>&1)"
    err=$?
    display "ambari-server stop: $out" $LOG_DEBUG
    if (( err != 0 )) ; then
      display "WARN: couldn't stop ambari server" $LOG_FORCE
    fi
    out="$(ambari-server reset -s 2>&1)"
    err=$?
    display "ambari-server reset: $out" $LOG_DEBUG
    if (( err != 0 )) ; then
      display "WARN: couldn't reset ambari server" $LOG_FORCE
    fi
  fi

  # install server rpm
  server_rpm="$(ls $AMBARI_SERVER_GLOB 2>/dev/null)"
  if [[ -z "$server_rpm" ]] ; then
    display "ERROR: Ambari server RPM missing" $LOG_FORCE
    exit 28
  fi
  # Note: the Oracle Java install takes a fair amount of time and yum does
  # thousands of progress updates. On a terminal this is fine but when output
  # is redirected to disk you get a *very* long record. The invoking script will
  # delete this one very long record in order to make the logfile more usable.
  out="$(yum -y install $server_rpm 2>&1)"
  err=$?
  display "ambari-server install: $out" $LOG_DEBUG
  if (( err != 0 && err != 1 )) ; then # 1--> nothing-to-do
    display "ERROR: ambari server install error $err" $LOG_FORCE
    exit 31
  fi

  cd -

  # setup the ambari-server
  # note: -s accepts all defaults with no prompting
  out="$(ambari-server setup -s 2>&1)"
  err=$?
  display "ambari-server setup: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: ambari server setup error $err" $LOG_FORCE
    exit 34
  fi

  # start the server
  out="$(ambari-server start 2>&1)"
  err=$?
  display "ambari-server start: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: ambari-server start error $err" $LOG_FORCE
    exit 37
  fi

  # start the server after a reboot
  out="$(chkconfig ambari-server on 2>&1)"
  display "ambari-server chkconfig on: $out" $LOG_DEBUG
}

# install_common: perform node installation steps independent of whether or not
# the node is to be the management server or simple a storage/data node.
#
function install_common(){

  # copy Ambari repo
  echo
  display "-- Copying Ambari repo file" $LOG_SUMMARY
  copy_ambari_repo

  # install epel
  echo
  display "-- Installing EPEL package" $LOG_SUMMARY
  install_epel
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

install_common

[[ $STORAGE_INSTALL == true ]] && install_ambari_agent
[[ $MGMT_INSTALL    == true ]] && install_ambari_server

cleanup_logfile

exit 0
#
# end of script
