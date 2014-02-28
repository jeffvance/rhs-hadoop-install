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
#  - sets selinux to permissive mode, if enabled
#  - tests if the fuse patch is installed in the running kernel, and if not
#    does a yum update kernel and marks the node for a reboot,
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
VERSION='1.04'
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
  display "   ... SELinux is: $out" $LOG_SUMMARY
 
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
  echo
  display "-- Verifying SELINUX setting:" $LOG_SUMMARY
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
