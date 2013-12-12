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
#  - ...
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


# install_plugin: copy the Hadoop-Gluster plug-in from the rhs install files to
# the appropriate Hadoop directory. Fatal errors exit script.
#
function install_plugin(){

  local PLUGIN_JAR='glusterfs-hadoop-.*.jar' # note: regexp not glob
  local USR_JAVA_DIR='/usr/share/java'
  local HADOOP_JAVA_DIR='/usr/lib/hadoop/lib/'
  local jar=''; local out; local err

  # set MATCH_DIR and MATCH_FILE vars if match
  match_dir "$PLUGIN_JAR" "$SUBDIR_FILES"
  [[ -z "$MATCH_DIR" ]] && {
        display "INFO: gluster-hadoop plugin not supplied" $LOG_INFO;
        return; }

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

  display "   ... Gluster-Hadoop plug-in install successful" $LOG_SUMMARY
  cd -
}

# install_common: perform node installation steps independent of whether or not
# the node is to be the management server or simple a storage/data node.
#
function install_common(){

  echo
  display "-- Setting up IP -> hostname mapping" $LOG_SUMMARY
  fixup_etc_hosts_file
  echo $NODE >/etc/hostname
  hostname $NODE
}

# install_storage: perform the installation steps needed when the node is a
# storage/data node.
#
function install_storage(){

  local i; local out

  # set this node's IP variable
  for (( i=0; i<$NUMNODES; i++ )); do
        [[ $NODE == ${HOSTS[$i]} ]] && break
  done
  IP=${HOST_IPS[$i]}

  # set up /etc/hosts to map ip -> hostname
  # install Gluster-Hadoop plug-in on agent nodes
  echo
  display "-- Verifying RHS-GlusterFS installation:" $LOG_SUMMARY
  install_plugin
}

# install_mgmt: perform the installations steps needed when the node is the
# management node.
#
function install_mgmt(){

  echo
  display "-- Management node is $NODE" $LOG_INFO
  display "   Special management node processing, if any, will be done by scripts in sub-directories" $LOG_INFO

  # nothing to do here (yet)...
}

# execute_extra_scripts: if there are any scripts within the extra sub-dirs
# then execute them now. All prep_node args are passed to the script; however,
# unfortunately, $@ cannot be used since the arrays are lost. Therefore, each
# arg is passed individually.
# Note: script errors are ignored and do not stop the next script from
#    executing. This may need to be changed later...
# Note: for an unknown reason, the 2 arrays need to be converted to strings
#   then passed to the script. This is not necessary when passing the same
#   arrays from install.sh to prep_node.sh but seems to be required here...
#
function execute_extra_scripts(){

  local f; local dir; local err

  echo
  [[ -z "$SUBDIR_XFILES" ]] && {
        display "No additional executable scripts found" $LOG_INFO;
        return; }

  display " --  Executing scripts in sub-directories..." $LOG_SUMMARY
  local tmp1="${HOSTS[@]}"    # convert array -> string
  local tmp2="${HOST_IPS[@]}"

  for f in $SUBDIR_XFILES ; do
      display "Begin executing: $f ..." $LOG_INFO
      dir="$(dirname $f)"; f="$(basename $f)"
      cd $dir
      ./$f $NODE $STORAGE_INSTALL $MGMT_INSTALL "$tmp1" "$tmp2" $MGMT_NODE \
           $VERBOSE $LOGFILE $DEPLOY_DIR "$RHN_USER" "$RHN_PASS"
      err=$?
      cd -
      (( err != 0 )) && display "$f error: $err" $LOG_INFO
      display "Done executing: $f" $LOG_INFO
      display '-----------------------' $LOG_INFO
      echo
  done
}


# ** main ** #
#            #
echo
display "$(date). Begin: $0" $LOG_REPORT

if [[ ! -d $DEPLOY_DIR ]] ; then
  display "$NODE: Directory '$DEPLOY_DIR' missing on $(hostname)" $LOG_FORCE
  exit -1
fi

cd $DEPLOY_DIR

if (( $(ls | wc -l) == 0 )) ; then
  display "$NODE: No files found in $DEPLOY_DIR" $LOG_FORCE
  exit -1
fi

# create SUBDIR_FILES variable which contains all files in all sub-dirs. There
# can be 0 or more sub-dirs. Note: devutils/ is not copied to each node.
DIRS="$(ls -d */ 2>/dev/null)"
# format for SUBDIR_FILES:  "dir1/file1 dir1/file2...dir2/fileN ..."
# format for SUBDIR_XFILES: "dir/x-file1 dir/x-file2 dir2/x-file3 ..."
if [[ -n "$DIRS" ]] ; then
   SUBDIR_FILES="$(find $DIRS -type f)";
   [[ -n "$SUBDIR_FILES" ]] &&
        SUBDIR_XFILES="$(find $SUBDIR_FILES -executable -name '*.sh')"
fi

install_common

[[ $STORAGE_INSTALL == true ]] && install_storage
[[ $MGMT_INSTALL    == true ]] && install_mgmt

# execute all shell scripts within sub-dirs, if any
execute_extra_scripts

echo
display "$(date). End: $0" $LOG_REPORT

[[ -n "$REBOOT_REQUIRED" ]] && exit 99 # tell install.sh a reboot is needed
exit 0
#
# end of script

