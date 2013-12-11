#!/bin/bash
#
# Copyright (c) 2013 Red Hat, Inc.
# License: Apache License v2.0
# Author: Jeff Vance <jvance@redhat.com>
#
# THIS SCRIPT IS NOT MEANT TO BE RUN STAND-ALONE. IT IS A COMPANION SCRIPT TO
# install.sh.
#
# This script is a companion script to install.sh and runs on a remote node. It
# prepares the hosting node for hadoop workloads ontop of red hat storage. 
#
# This script does the following on the host (this) node:
#  - modifes /etc/hosts to include all hosts ip/hostname for the cluster
#  - sets up the sudoers file
#  - registers this node with RHN (red hat support network)
#  - ensures that ntp is running correctly
#  - disables the firewall via iptables
#  - set selinux to permissive mode
#
# Additionally, depending on the contents of the tarball (see devutils/
# mk_tarball), this script may install the following:
#  - gluster-hadoop plug-in jar file,
#  - FUSE kernel patch,
#  - ktune.sh performance script
#
# Lastly, if there are any executable files (expected to be shell scripts)
# within any sub-directories found under the deployment dir, they are 
# executed (and passed the same args as prep_node in the same order).
# Note: executables are invoked after all tasks above are completed.
# Note: the order of execution is alphabetical based on 1) sub-dir name and 
#   2) shell script name.
# Note: sub-dir naming such as 001-foo and 002-bar can force the desired
#    execution order.
#
# Please read the README file.
#
# Arguments (all positional):
#   $1=self hostname*, $2=install storage flag*, $3=install mgmt server flag*,
#   $4=HOSTS(array)*, $5=HOST IP-addrs(array)*, $6=management server hostname*,
#   $7=verbose value*, $8=special logfile*, $9=working dir, $10=rhn user, 
#   $11=rhn user password
# '*' means required argument, others are optional.
#
# Note: as of now, in prep_node.sh, the "install mgmt server" flag is ignored.
#   However, supporting scripts executed by prep_node are passed this flag and
#   may act upon its setting.
#
# Note on passing arrays: the caller (install.sh) needs to surround the array
#   values with embedded double quotes, eg. "\"${ARRAY[@]}\""

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
. ${DEPLOY_DIR}functions


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

# verify_ntp: verify that ntp is installed, running, and synchronized.
#
function verify_ntp(){

  local err; local out

  # run ntpd on reboot
  out="$(chkconfig ntpd on 2>&1)"
  err=$?
  display "chkconfig ntpd on: $out" $LOG_DEBUG
  (( err != 0 )) &&  display "WARN: chkconfig ntpd on error $err" $LOG_FORCE

  # stop ntpd so that ntpd -qg can potentially do a large time change
  ps -C ntpd >& /dev/null
  if (( $? == 0 )) ; then
    out="$(service ntpd stop 2>&1)"
    display "ntpd stop: $out" $LOG_DEBUG
    sleep 1
    ps -C ntpd >& /dev/null # see if ntpd is stopped now...
    (( $? == 0 )) && display "WARN: ntpd did NOT stop" $LOG_FORCE
  fi

  # set time to ntp clock time now (ntpdate is being deprecated)
  # note: ntpd can't be running...
  out="$(ntpd -qg 2>&1)"
  err=$?
  display "ntpd -qg: $out" $LOG_DEBUG
  (( err != 0 )) && display "WARN: ntpd -qg (aka ntpdate) error $err" \
	$LOG_FORCE

  # start ntpd
  out="$(service ntpd start 2>&1)"
  err=$?
  display "ntpd start: $out" $LOG_DEBUG
  (( err != 0 )) && display "WARN: ntpd start error $err" $LOG_FORCE

  # used to invoke ntpstat to verify the synchronization state, but error 1 was
  # always returned if the above ntpd -qg cmd did a large time change. Thus, we
  # no longer call ntpstat since the node will "realtively" soon sync up.
}

# verify_fuse: verify this node has the correct kernel FUSE patch, and if not
# it will be installed and this node will need to be rebooted. Sets the global
# REBOOT_REQUIRED variable if the fuse patch is installed.
#
function verify_fuse(){

  local FUSE_TARBALL_RE='fuse-.*.tar.gz' # note: regexp not glob
  local FUSE_TARBALL
  local out; local err
  local FUSE_CHK_CMD="rpm -q --changelog kernel-2.6.32-358.28.1.el6.x86_64 | less | head -20 | grep fuse"

  out="$($FUSE_CHK_CMD)"
  if [[ -n "$out" ]] ; then # assume fuse patch has been installed
    display "   ... verified" $LOG_DEBUG
    return
  fi

  display "   In theory the FUSE patch is needed..." $LOG_INFO

  # set MATCH_DIR and MATCH_FILE vars if match
  match_dir "$FUSE_TARBALL_RE" "$SUBDIR_FILES"
  [[ -z "$MATCH_DIR" ]] && {
	display "INFO: FUSE patch not supplied" $LOG_INFO;
	return; }

  cd $MATCH_DIR
  FUSE_TARBALL=$MATCH_FILE

  display "-- Installing FUSE patch via $FUSE_TARBALL ..." $LOG_INFO
  echo
  rm -rf fusetmp # scratch dir
  mkdir fusetmp

  out="$(tar -C fusetmp/ -xzf $FUSE_TARBALL 2>&1)"
  err=$?
  display "untar fuse: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: untar fuse error $err" $LOG_FORCE
    exit 13
  fi

  out="$(yum -y install fusetmp/*.rpm 2>&1)"
  err=$?
  display "fuse install: $out" $LOG_DEBUG
  if (( err != 0 && err != 1 )) ; then # 1--> nothing to do
    display "ERROR: fuse install error $err" $LOG_FORCE
    exit 16
  fi

  display "   A reboot of $NODE is required and will be done automatically" \
        $LOG_INFO
  echo
  REBOOT_REQUIRED=true
  cd -
}


# sudoers: copy the packaged sudoers file to /etc/sudoers.d/ and set its
# permissions. Note: it is ok if the sudoers file is not included in the
# install package.
#
function sudoers(){

  local SUDOER_DIR='/etc/sudoers.d'
  local SUDOER_GLOB='*sudoer*'
  local sudoer_file="$(ls $SUDOER_GLOB 2>/dev/null)" # except 0 or 1 only!
  local SUDOER_PATH="$SUDOER_DIR/$sudoer_file"
  local SUDOER_PERM='440'
  local out; local err

  echo
  display "-- Installing sudoers file..." $LOG_SUMMARY

  [[ -z "$sudoer_file" ]] && {
	display "INFO: sudoers file not supplied in package" $LOG_INFO;
	return; }

  [[ -d "$SUDOER_DIR" ]] || {
    display "   Creating $SUDOER_DIR..." $LOG_DEBUG;
    mkdir -p $SUDOER_DIR; }

  # copy packaged sudoers file to correct location
  cp $sudoer_file $SUDOER_PATH
  if [[ ! -f $SUDOER_PATH ]] ; then
    display "ERROR: sudoers copy to $SUDOER_PATH failed" $LOG_FORCE
    exit 20
  fi

  out="$(chmod $SUDOER_PERM $SUDOER_PATH 2>&1)"
  err=$?
  display "sudoer chmod: $out" $LOG_DEBUG
  (( err != 0 )) && display "WARN: sudoers chmod error $err" $LOG_FORCE
}

# disable_firewall: use iptables to disable the firewall.
#
function disable_firewall(){

  local out; local err

  out="$(iptables -F)" # sure fire way to disable iptables
  err=$?
  display "iptables: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "WARN: iptables error $err" $LOG_FORCE
  fi

  out="$(chkconfig iptables off 2>&1)" # keep disabled after reboots
  display "chkconfig off: $out" $LOG_DEBUG
}

# install_common: perform node installation steps independent of whether or not
# the node is to be the management server or simple a storage/data node.
#
function install_common(){

  # set SELinux to permissive if it's enabled
  check_selinux

  # disable firewall
  echo
  display "-- Disable firewall" $LOG_SUMMARY
  disable_firewall

  echo
  display "-- Setting up IP -> hostname mapping" $LOG_SUMMARY
  fixup_etc_hosts_file
  echo $NODE >/etc/hostname
  hostname $NODE

  # set up sudoers file for mapred and yarn users
  sudoers

  # rhn register, if username/pass provided
  rhn_register

  # verify NTP setup and sync clock
  echo
  display "-- Verifying NTP is running" $LOG_SUMMARY
  verify_ntp
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

  # verify FUSE patch on data (agent) nodes, if not installed yum install it
  echo
  display "-- Verifying FUSE patch installation:" $LOG_SUMMARY
  verify_fuse

  # apply the tuned-admin rhs-high-throughput profile
  echo
  display "-- Applying the rhs-high-throughput profile using tuned-adm" \
	$LOG_SUMMARY
  apply_tuned
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
display "$(date). Begin: prep_node" $LOG_REPORT

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

# remove special logfile, start "clean" each time script is invoked
rm -f $LOGFILE

install_common

[[ $STORAGE_INSTALL == true ]] && install_storage
[[ $MGMT_INSTALL    == true ]] && install_mgmt

# execute all shell scripts within sub-dirs, if any
execute_extra_scripts

echo
display "$(date). End: prep_node" $LOG_REPORT

[[ -n "$REBOOT_REQUIRED" ]] && exit 99 # tell install.sh a reboot is needed
exit 0
#
# end of script
