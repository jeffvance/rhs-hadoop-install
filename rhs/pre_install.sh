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
#  - tests if the fuse patch is installed in the running kernel, and if not
#    does a yum update kernel and marks the node for a reboot,
#  - installs the ktune.sh performance script if it exists in rhs/ or in any of
#    its sub-dirs.
#
# Please read the README file.
#
# Arguments (all positional):
#   $1=associative array, passed by *declaration*, containing many individual
#      arg values. Note: special care needed when passing and receiving
#      associative arrays,
#   $2=HOSTS(array),
#   $3=HOST IP-addrs(array).
#
# Note on passing arrays: the caller needs to surround the array values with
#   embedded double quotes, eg. "\"${ARRAY[@]}\""
# Note on passing associative arrays: the caller needs to pass the declare -A
#   command line which initializes the array. The receiver then evals this
#   string in order to set its own assoc array.

#
# constants and args
VERSION='1.03'
eval 'declare -A _ARGS='${1#*=} # delete the "declare -A name=" portion of arg
NODE="${_ARGS[NODE]}"
STORAGE_INSTALL="${_ARGS[INST_STORAGE]}" # true or false
MGMT_INSTALL="${_ARGS[INST_MGMT]}"       # true or false
VERBOSE="${_ARGS[VERBOSE]}"  # needed by display()
LOGFILE="${_ARGS[PREP_LOG]}" # needed by display()
DEPLOY_DIR="${_ARGS[REMOTE_DIR]}"
HOSTS=($2)
HOST_IPS=($3)

#echo -e "*** $(basename $0) 1=$1\n1=$(declare -p _ARGS),\n2=${HOSTS[@]},\n3=${HOST_IPS[@]}"

# source common constants and functions
source ${DEPLOY_DIR}functions


# install_plugin: if a plugin jar file is provided in any of the included sub-
# directories then copy it to the correct location. Otherwise, yum install the
# rhs-hadoop plugin package, which also copies the jar file to the correct
# directory.
# NOTE: not currently invoked since the rhs-hadoop plugin package is now part
#   of the RHS 2.1.1+ ISO.
#
function install_plugin(){

  local PLUGIN_JAR='glusterfs-hadoop-.*.jar' # note: regexp not glob
  local PLUGIN_PKG='rhs-hadoop'
  local USR_JAVA_DIR='/usr/share/java'
  local HADOOP_JAVA_DIR='/usr/lib/hadoop/lib/'
  local jar=''; local out; local err

  # set MATCH_DIR and MATCH_FILE vars if match
  match_dir "$PLUGIN_JAR" "$SUBDIR_FILES"
  if [[ -n "$MATCH_DIR" ]]; then  # found packaged plugin jar file
    cd $MATCH_DIR
    jar="$MATCH_FILE"
    display "-- Installing Gluster-Hadoop plug-in ($jar)..." $LOG_INFO

    # create target dirs if they does not exist
    [[ -d $USR_JAVA_DIR ]]    || mkdir -p $USR_JAVA_DIR
    [[ -d $HADOOP_JAVA_DIR ]] || mkdir -p $HADOOP_JAVA_DIR

    # copy jar and create symlink
    out="$(cp -uf $jar $USR_JAVA_DIR 2>&1)"
    err=$?
    display "plugin cp: $out" $LOG_DEBUG
    if (( err != 0 )) ; then
      display "ERROR: plugin copy error $err" $LOG_FORCE
      exit 5
    fi

    rm -f $HADOOP_JAVA_DIR/$jar
    out="$(ln -s $USR_JAVA_DIR/$jar $HADOOP_JAVA_DIR/$jar 2>&1)"
    err=$?
    display "plugin symlink: $out" $LOG_DEBUG
    if (( err != 0 )) ; then
      display "ERROR: plugin symlink error $err" $LOG_FORCE
      exit 7
    fi
    cd -

  elif yum -q $PLUGIN_PKG >&/dev/null ; then # pgk available
    # yum install rhs-hadoop pkg
    out="$(yum -y install $PLUGIN_PKG)"
    err=$?
    display "yum install $PLUGIN_PKG plugin: $out" $LOG_INFO
    if (( err != 0 )) ; then
      display "ERROR: yum install error $err" $LOG_FORCE
      exit 8
    fi

  else
    display "ERROR: \"$PLUGIN_PKG\" package is not available" $LOG_FORCE
    display "       This package contains the hadoop plugin" $LOG_FORCE
    exit 9
  fi
  display "   ... $PLUGIN_PKG plugin install successful" $LOG_SUMMARY
}

# apply_tuned: apply the tuned-adm peformance tuning for RHS.
#
function apply_tuned(){

  local out; local err
  local TUNE_PROFILE='rhs-high-throughput'
  local TUNE_DIR="/etc/tune-profiles/$TUNE_PROFILE"
  local TUNE_FILE='ktune.sh'
  local TUNE_PATH="$TUNE_DIR/$TUNE_FILE"
  local TUNE_PATH_BAK="$TUNE_PATH.orig"
  local TUNE_PERMS=755 # rwxr-xr-x

  # set MATCH_DIR and MATCH_FILE vars if match
  match_dir "$TUNE_FILE" "$SUBDIR_FILES"
  [[ -z "$MATCH_DIR" ]] && {
	display "INFO: $TUNE_FILE file not supplied" $LOG_INFO
	return; }

  cd $MATCH_DIR

  # replace ktune.sh
  [[ -f $TUNE_PATH_BAK ]] || mv $TUNE_PATH $TUNE_PATH_BAK
  out="$(cp -f $TUNE_FILE $TUNE_PATH)"
  err=$?
  display "$TUNE_FILE cp: $out" $LOG_DEBUG
  if [[ ! -f $TUNE_PATH ]] ; then
    display "ERROR: cp of $TUNE_FILE to $TUNE_DIR error $err" $LOG_FORCE
    exit 13 
  fi
  chmod $TUNE_PERMS $TUNE_PATH

  # run profile
  out="$(tuned-adm profile $TUNE_PROFILE 2>&1)"
  err=$?
  display "tuned-adm: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: tuned-adm error $err" $LOG_FORCE
    exit 15
  fi
  cd -
}

# check_selinux: if selinux is enabled then set it to permissive. This seems
# to be a requirement for HDP.
#
function check_selinux(){

  local out
  local CONF='/etc/sysconfig/selinux' # symlink to /etc/selinux/config
  local SELINUX_KEY='SELINUX='
  local PERMISSIVE='permissive'; local ENABLED='enabled'

  # report selinux state
  out=$(sestatus | head -n 1 | awk '{print $3}') # enforcing, permissive
  echo
  display "SELinux is: $out" $LOG_SUMMARY
 
  [[ "$out" != "$ENABLED" ]] && return # done

  # set selinux to permissive (audit errors reported but not enforced)
  setenforce permissive

  # keep selinux permissive on reboots
  if [[ ! -f $CONF ]] ; then
    display "WARN: SELinux config file $CONF missing" $LOG_FORCE
    return # nothing more to do...
  fi
  # config SELINUX=permissive which takes effect the next reboot
  display "-- Setting SELinux to permissive..." $LOG_SUMMARY
  sed -i -e "/^$SELINUX_KEY/c\\$SELINUX_KEY$PERMISSIVE" $CONF
}

# verify_fuse: verify this node has the correct kernel FUSE patch, and if not
# it will be installed and this node will need to be rebooted. Sets the global
# REBOOT_REQUIRED variable if the fuse patch is installed.
#
function verify_fuse(){

  local out; local err; local FUSE_OUT='fuse_chk.out'
  FUSE_SRCH_STRING='fuse: drop dentry on failed revalidate (Brian Foster) \[1009756 924014\]'
  local KERNEL="$(uname -r)"

  rpm -q --changelog kernel-$KERNEL >$FUSE_OUT # on the running kernel
  if (( $? == 0 )) && grep -q "$FUSE_SRCH_STRING" $FUSE_OUT ; then
    display "   ... verified on kernel $KERNEL" $LOG_DEBUG
    return
  fi

  display "   In theory the FUSE patch is needed..." $LOG_INFO

  # do an unconditional yum update kernel and set this node to be rebooted
  display "Doing yum update kernel to apply fuse patches. This will take several minutes..." $LOG_INFO
  out="$(yum -y update kernel)"
  err=$?
  display "yum update: $out" $LOG_DEBUG
  (( err != 0 )) && display "WARN $err: yum update. Continuing..." $LOG_FORCE

  display "A reboot of $NODE is required and will be done automatically" \
        $LOG_INFO

  echo
  REBOOT_REQUIRED=true
}

# install_common: perform node installation steps independent of whether or not
# the node is to be the management server or a storage/data node.
#
function install_common(){

  # set SELinux to permissive if it's enabled
  check_selinux

}

# install_storage: perform the installation steps needed when the node is a
# storage/data node.
#
function install_storage(){

  local out

  # verify FUSE patch on data (agent) nodes, if not installed yum install it
  echo
  display "-- Verifying FUSE patch installation:" $LOG_SUMMARY
  verify_fuse

  # apply the tuned-admin rhs-high-throughput profile
  echo
  display "-- Applying the rhs-high-throughput profile using tuned-adm" \
	$LOG_SUMMARY

  # install the rhs-hadoop plugin
  # NOTE: no longer needed since the RHS ISO contains the plugin
  #echo
  #display "-- Installing the rhs-hadoop plugin (jar file)" $LOG_SUMMARY
  #install_plugin
}

# install_mgmt: perform the installation steps needed when the node is the
# management node.
#
function install_mgmt(){

  local err
 
  # nothing to do here (yet)...
}


# ** main ** #
#            #
echo
echo "$(basename $0), version: $VERSION"

# create SUBDIR_FILES variable which contains all files in all sub-dirs. There 
# can be 0 or more sub-dirs. Format for SUBDIR_FILES:
#   "dir1/file1 dir1/f2 dir2/dir3/f ..."
# Note: devutils/ is not copied to each node.
DIRS="$(ls -d */ 2>/dev/null)" 
[[ -n "$DIRS" ]] && SUBDIR_FILES="$(find $DIRS -type f)"

install_common

[[ $STORAGE_INSTALL == true ]] && install_storage
[[ $MGMT_INSTALL    == true ]] && install_mgmt

echo
[[ -n "$REBOOT_REQUIRED" ]] && exit 99 # tell invoking script reboot is needed
exit 0
#
# end of script
