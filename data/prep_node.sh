#!/bin/bash
#
# Copyright (c) 2013 Red Hat, Inc.
# License: Apache License v2.0
# Author: Jeff Vance <jvance@redhat.com>
#
# THIS SCRIPT IS NOT MEANT TO BE RUN STAND-ALONE. IT IS A COMPANION SCRIPT TO
# INSTALL.SH
#
# This script is a companion script to install.sh and runs on a remote node. It
# does the following:
#  - reports the gluster version,
#  - installs the gluster-hadoop plug-in,
#  - checks if NTP is running and synchronized,
#  - yum installs the ambai agent and/or ambari-server rpms depending on passed
#    in arguments.
#  - installs the FUSE patch if it has not already been installed.
#
# Arguments (all positional):
#   $1=self hostname*, $2=install storage flag*, $3=install mgmt server flag*,
#   $4=HOSTS(array)*, $5=HOST IP-addrs(array)*, $6=management server hostname*,
#   $7=verbose value*, $8=special logfile*, $9=working dir, $10=rhn user, 
#   $11=rhn user password
# '*' means required argument, others are optional.
#
# Note on passing arrays: the caller (install.sh) needs to surround the array
# values with embedded double quotes, eg. "\"${ARRAY[@]}\""

# constants and args
NODE=$1
STORAGE_INSTALL=$2 # true or false
MGMT_INSTALL=$3    # true or false
HOSTS=($4)
HOST_IPS=($5)
MGMT_NODE="$6" # note: this node can be inside or outside the storage cluster
VERBOSE=$7
PREP_LOG=$8
DEPLOY_DIR=${9:-/tmp/RHS-Ambari-install/data/}
RHN_USER=${10:-}
RHN_PASS=${11:-}
#echo -e "*** $(basename $0)\n 1=$NODE, 2=$STORAGE_INSTALL, 3=$MGMT_INSTALL, 4=${HOSTS[@]}, 5=${HOST_IPS[@]}, 6=$MGMT_NODE, 7=$VERBOSE, 8=$PREP_LOG, 9=$DEPLOY_DIR, 10=$RHN_USER, 11=$RHN_PASS"

NUMNODES=${#HOSTS[@]}
AMBARI_TMPDIR=${DEPLOY_DIR}tmpAmbari
# log threshold values (copied from install.sh)
LOG_DEBUG=0
LOG_INFO=1    # default for --verbose
LOG_SUMMARY=2 # default
LOG_REPORT=3  # suppress all output, other than final reporting
LOG_QUIET=9   # value for --quiet = suppress all output
LOG_FORCE=99  # force write regardless of VERBOSE setting


# display: write all messages to the special logfile which will be copied to 
# the "install-from" host, and potentially write the message to stdout. 
# $1=msg, $2=msg prioriy (optional, default=summary)
#
function display(){

  local pri=${2:-$LOG_SUMMARY} 

  echo "$1" >> $PREP_LOG
  (( pri >= VERBOSE )) && echo -e "$1"
}

# fixup_etc_host_file: append all ips + hostnames to /etc/hosts, unless the
# hostnames already exist.
#
function fixup_etc_hosts_file(){ 

  local host=; local ip=; local hosts_buf=''; local i

  for (( i=0; i<$NUMNODES; i++ )); do
        host="${HOSTS[$i]}"
        ip="${HOST_IPS[$i]}"
	# skip if host already present in /etc/hosts
        if grep -qs "$host" /etc/hosts; then # found self node
          continue # skip to next node
        fi
        hosts_buf+="$ip $host # auto-generated by RHS install"$'\n' # \n at end
  done
  if (( ${#hosts_buf} > 2 )) ; then
    hosts_buf=${hosts_buf:0:${#hosts_buf}-1} # remove \n for last host entry
    display "  appending \"$hosts_buf\" to /etc/hosts" $LOG_DEBUG
    echo "$hosts_buf" >>/etc/hosts
  fi
}

# install_plugin: copy the Hadoop-Gluster plug-in from the rhs install files to
# the appropriate Hadoop directory. Fatal errors exit script.
#
function install_plugin(){

  local USR_JAVA_DIR='/usr/share/java'
  local HADOOP_JAVA_DIR='/usr/lib/hadoop/lib/'
  local jar=''; local out; local err

  jar=$(ls glusterfs-hadoop*.jar)
  if [[ -z "$jar" ]] ; then
    display "  Gluster Hadoop plug-in missing in $DEPLOY_DIR" $LOG_FORCE
    exit 3
  fi

  display "-- Installing Gluster-Hadoop plug-in ($jar)..." $LOG_INFO
  # create target dirs if they does not exist
  [[ -d $USR_JAVA_DIR ]]    || mkdir -p $USR_JAVA_DIR
  [[ -d $HADOOP_JAVA_DIR ]] || mkdir -p $HADOOP_JAVA_DIR

  # copy jar and create symlink
  out=$(cp -uf $jar $USR_JAVA_DIR 2>&1)
  err=$?
  display "plugin cp: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: plugin copy error $err" $LOG_FORCE
    exit 5
  fi

  rm -f $HADOOP_JAVA_DIR/$jar
  out=$(ln -s $USR_JAVA_DIR/$jar $HADOOP_JAVA_DIR/$jar 2>&1)
  err=$?
  display "plugin symlink $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: plugin symlink error $err" $LOG_FORCE
    exit 7
  fi

  display "   ... Gluster-Hadoop plug-in install successful" $LOG_SUMMARY
}

# copy_ambari_repo: copy the ambari.repo file to the correct location.
#
function copy_ambari_repo(){
 
  local REPO='ambari.repo'; local REPO_DIR='/etc/yum.repos.d'
  local out; local err

  if [[ ! -f $REPO ]] ; then
    display "ERROR: \"$REPO\" file missing" $LOG_FORCE
    exit 8
  fi
  [[ -d $REPO_DIR ]] || mkdir -p $REPO_DIR

  out=$(cp $REPO $REPO_DIR 2>&1)
  err=$?
  display "ambari repo cp: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: ambari repo copy $err" $LOG_FORCE
    exit 12
  fi
}

# install_epel: install the epel rpm. Note: epel package is not part of the
# install tarball and therefore must be installed over the internet via the
# ambari repo file. It is required that the ambari.repo file has been copied 
# to the correct dir prior to invoking this function.
#
function install_epel(){

  local out; local err
 
  out=$(yum -y install epel-release 2>&1)
  err=$?
  display "install epel: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: yum install epel-release error $err" $LOG_FORCE
    exit 14
  fi
}

# install_ambari_agent: untar the ambari rpm tarball, yum install the ambari
# agent rpm, modify the .ini file to point to the ambari server, start the
# agent, and set up agent to start automatically after a reboot.
#
function install_ambari_agent(){

  local agent_rpm=''; local out; local err
  local ambari_ini='/etc/ambari-agent/conf/ambari-agent.ini'
  local SERVER_SECTION='server'; SERVER_KEY='hostname='
  local KEY_VALUE="$MGMT_NODE"
  local AMBARI_AGENT_PID='/var/run/ambari-agent/ambari-agent.pid'

  [[ -d $AMBARI_TMPDIR ]] || mkdir $AMBARI_TMPDIR 2>&1
  # extract ambari rpms
  out=$(tar -C $AMBARI_TMPDIR -xzf ambari-*.tar.gz 2>&1)
  err=$?
  display "untar ambari RPMs: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: untar ambari RPMs $err" $LOG_FORCE
    exit 16
  fi

  pushd $AMBARI_TMPDIR > /dev/null

  # stop agent if running
  if [[ -f $AMBARI_AGENT_PID ]] ; then
    display "   stopping ambari-agent" $LOG_INFO
    out=$(ambari-agent stop 2>&1)
    err=$?
    display "ambari-agent stop: $out" $LOG_DEBUG
    if (( err != 0 )) ; then
      display "WARN: couldn't stop ambari agent" $LOG_FORCE
    fi
  fi

  # install agent rpm
  agent_rpm=$(ls ambari-agent-*.rpm)
  if [[ -z "$agent_rpm" ]] ; then
    display "ERROR: Ambari agent RPM missing" $LOG_FORCE
    exit 18
  fi
  out=$(yum -y install $agent_rpm 2>&1)
  err=$?
  display "ambari-agent install: $out" $LOG_DEBUG
  if (( err != 0 && err != 1 )) ; then # 1--> nothing-to-do
    display "ERROR: ambari-agent install error $err" $LOG_FORCE
    exit 20
  fi

  popd > /dev/null

  # modify the agent's .ini file's server hostname value
  display "  modifying $ambari_ini file" $LOG_DEBUG
  sed -i -e "/\[${SERVER_SECTION}\]/,/${SERVER_KEY}/s/=.*$/=${KEY_VALUE}/" $ambari_ini

  # start the agent
  out=$(ambari-agent start 2>&1)
  err=$?
  display "ambari-agent start: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: ambari-agent start error $err" $LOG_FORCE
    exit 22
  fi

  # start agent after reboot
  out=$(chkconfig ambari-agent on 2>&1)
  display "ambari-agent chkconfig on: $out" $LOG_DEBUG
}

# install_ambari_server: yum install the ambari server rpm, setup start the
# server, start ambari server, and start the server after a reboot.
#
function install_ambari_server(){

  local server_rpm=''; local out; local err
  local AMBARI_SERVER_PID='/var/run/ambari-server/ambari-server.pid'

  [[ -d $AMBARI_TMPDIR ]] || mkdir $AMBARI_TMPDIR 2>&1
  # extract ambari rpms
  out=$(tar -C $AMBARI_TMPDIR -xzf ambari-*.tar.gz 2>&1)
  err=$?
  display "untar ambari RPMs: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: untar ambari RPMs error $err" $LOG_FORCE
    exit 24
  fi

  pushd $AMBARI_TMPDIR > /dev/null

  # stop and reset server if running
  if [[ -f $AMBARI_SERVER_PID ]] ; then
    display "   stopping ambari-server" $LOG_INFO
    out=$(ambari-server stop 2>&1)
    err=$?
    display "ambari-server stop: $out" $LOG_DEBUG
    if (( err != 0 )) ; then
      display "WARN: couldn't stop ambari server" $LOG_FORCE
    fi
    out=$(ambari-server reset -s 2>&1)
    err=$?
    display "ambari-server reset: $out" $LOG_DEBUG
    if (( err != 0 )) ; then
      display "WARN: couldn't reset ambari server" $LOG_FORCE
    fi
  fi

  # install server rpm
  server_rpm=$(ls ambari-server-*.rpm)
  if [[ -z "$server_rpm" ]] ; then
    display "ERROR: Ambari server RPM missing" $LOG_FORCE
    exit 26
  fi
  # Note: the Oracle Java install takes a fair amount of time and yum does
  # thousands of progress updates. On a terminal this is fine but when output
  # is redirected to disk you get a *very* long record. The invoking script will
  # delete this one very long record in order to make the logfile more usable.
  out=$(yum -y install $server_rpm 2>&1)
  err=$?
  display "ambari-server install: $out" $LOG_DEBUG
  if (( err != 0 && err != 1 )) ; then # 1--> nothing-to-do
    display "ERROR: ambari server install error $err" $LOG_FORCE
    exit 28
  fi

  popd > /dev/null

  # setup the ambari-server
  # note: -s accepts all defaults with no prompting
  out=$(ambari-server setup -s 2>&1)
  err=$?
  display "ambari-server setup: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: ambari server setup error $err" $LOG_FORCE
    exit 30
  fi

  # start the server
  out=$(ambari-server start 2>&1)
  err=$?
  display "ambari-server start: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: ambari-server start error $err" $LOG_FORCE
    exit 32
  fi

  # start the server after a reboot
  out=$(chkconfig ambari-server on 2>&1)
  display "ambari-server chkconfig on: $out" $LOG_DEBUG
}

# verify_java: verify the version of Java on NODE. Fatal errors exit script.
# NOTE: currenly not in use.
function verify_java(){

  local err
  local TEST_JAVA_VER="1.6"

  which java >&/dev/null
  err=$?
  if (( $err == 0 )) ; then
    JAVA_VER=$(java -version 2>&1 | head -n 1 | cut -d\" -f 2)
    if [[ ! ${JAVA_VER:0:${#TEST_JAVA_VER}} == $TEST_JAVA_VER ]] ; then
      display "   Current Java is $JAVA_VER, expected $TEST_JAVA_VER." \
	$LOG_FORCE
      display "   Download Java $TEST_JAVA_VER JRE from Oracle now." \
	$LOG_FORCE
      err=1
    else
      display "   ... Java version $JAVA_VER verified" $LOG_INFO
    fi
  else
    display "   Java is not installed. Download Java $TEST_JAVA_VER JRE from Oracle now." $LOG_FORCE
    err=35
  fi
  (( $err == 0 )) || exit $err
}

# verify_ntp: verify that ntp is installed, running, and synchronized.
#
function verify_ntp(){

  local err; local out

  # run ntpd on reboot
  out=$(chkconfig ntpd on 2>&1)
  display "chkconfig on: $out" $LOG_DEBUG

  # start ntpd if not running
  ps -C ntpd >& /dev/null
  if (( $? != 0 )) ; then
    display "   Starting ntpd" $LOG_DEBUG
    out=$(service ntpd start 2>&1)
    display "ntpd start: $out" $LOG_DEBUG
    ps -C ntpd >& /dev/null # see if ntpd is running now...
    if (( $? != 0 )) ; then
      display "WARN: ntpd did NOT start" $LOG_FORCE
      return # no point in doing the rest...
    fi
  fi

  # set time now (ntpdate is being deprecated)
  out=$(ntpd -qg 2>&1)
  err=$?
  display "ntpd -qg: $out" $LOG_DEBUG
  (( err != 0 )) && display "WARN: ntpd -qg (aka ntpdate) error $err" $LOG_FORCE
  # report ntp synchronization state
  ntpstat >& /dev/null
  err=$?
  if (( err == 0 )) ; then 
    display "   NTP is synchronized..." $LOG_DEBUG
  elif (( $err == 1 )) ; then
    display "   NTP is NOT synchronized..." $LOG_INFO
  else
    display "   WARNING: NTP state is indeterminant..." $LOG_FORCE
  fi
}

# rhn_register: rhn register $NODE if a rhn username and password were passed.
#
function rhn_register(){

  local out; local err

  if [[ -n "$RHN_USER" && -n "$RHN_PASS" ]] ; then
    echo
    display "-- RHN registering with provided rhn user and password" \
	$LOG_INFO
    out=$(rhnreg_ks --profilename="$NODE" --username="$RHN_USER" --password="$RHN_PASS" --force 2>&1)
    err=$?
    display "rhn_register: $out" $LOG_DEBUG
    if (( err != 0 )) ; then
      display "ERROR: rhn_register error $err" $LOG_FORCE
      exit 38
    fi
  fi
}

# verify_fuse: verify this node has the correct kernel FUSE patch installed. If
# not then it will be installed and a global variable is set to indicate that
# this node needs to be rebooted. There is no shell command/utility to report
# whether or not the FUSE patch has been installed (eg. uname -r doesn't), so
# a file is used for this test.
#
function verify_fuse(){

  local FUSE_TARBALL='fuse-*.tar.gz'; local out; local err

  # if file exists then fuse patch installed
  local FUSE_INSTALLED='/tmp/FUSE_INSTALLED' # Note: deploy dir is rm'd

  if [[ -f "$FUSE_INSTALLED" ]]; then # file exists, assume installed
    display "   ... verified" $LOG_DEBUG
    return
  fi

  display "-- Installing FUSE patch which may take more than a few seconds..." \
	$LOG_INFO
  echo
  rm -rf fusetmp  # scratch dir
  mkdir fusetmp
  if (( $(ls $FUSE_TARBALL|wc -l) != 1 )) ; then
    display "ERROR: missing or extra FUSE tarball" $LOG_FORCE
    exit 40
  fi

  out=$(tar -C fusetmp/ -xzf $FUSE_TARBALL 2>&1)
  err=$?
  display "untar fuse: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: untar fuse error $err" $LOG_FORCE
    exit 42
  fi

  out=$(yum -y install fusetmp/*.rpm 2>&1)
  err=$?
  display "fuse install: $out" $LOG_DEBUG
  if (( err != 0 && err != 1 )) ; then # 1--> nothing to do
    display "ERROR: fuse install error $err" $LOG_FORCE
    exit 44
  fi

  # create kludgy fuse-has-been-installed file
  touch $FUSE_INSTALLED
  display "   A reboot of $NODE is required and will be done automatically" \
	$LOG_INFO
  echo
  REBOOT_REQUIRED=true
}

# sudoers: create the /etc/sudoers.d/20_gluster file if not present, add the
# mapred and yarn users to it (if not present) and set its permissions.
#
function sudoers(){

  local SUDOER_DIR='/etc/sudoers.d'
  local SUDOER_PATH="$SUDOER_DIR/20_gluster" # 20 is somewhat arbitrary
  local SUDOER_PERM='440'
  local SUDOER_ACC='ALL= NOPASSWD: /usr/bin/getfattr'
  local mapred='mapred'; local yarn='yarn'
  local MAPRED_SUDOER="$mapred $SUDOER_ACC"
  local YARN_SUDOER="$yarn $SUDOER_ACC"
  local out; local err

  echo
  display "-- Prepping $SUDOER_PATH for user access exceptions..." $LOG_SUMMARY

  if [[ ! -d "$SUDOER_DIR" ]] ; then
    display "   Creating $SUDOER_DIR..." $LOG_DEBUG
    mkdir -p $SUDOER_DIR
  fi

  if ! grep -qs $mapred $SUDOER_PATH ; then
    display "   Appending \"$MAPRED_SUDOER\" to $SUDOER_PATH" $LOG_INFO
    echo "$MAPRED_SUDOER" >> $SUDOER_PATH
  fi
  if ! grep -qs $yarn $SUDOER_PATH ; then
    display "   Appending \"$YARN_SUDOER\" to $SUDOER_PATH" $LOG_INFO
    echo "$YARN_SUDOER"  >> $SUDOER_PATH
  fi

  out=$(chmod $SUDOER_PERM $SUDOER_PATH 2>&1)
  err=$?
  display "sudoer chmod: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: sudoers chmod error $err" $LOG_FORCE
    exit 46
  fi
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

  # replace ktune.sh
  [[ -f $TUNE_PATH_BAK ]] || mv $TUNE_PATH $TUNE_PATH_BAK
  out=$(cp -f $TUNE_FILE $TUNE_PATH)
  err=$?
  display "$TUNE_FILE cp: $out" $LOG_DEBUG
  if [[ ! -f $TUNE_PATH ]] ; then
    display "ERROR: cp of $TUNE_FILE to $TUNE_DIR error $err" $LOG_FORCE
    exit 48 
  fi
  chmod $TUNE_PERMS $TUNE_PATH

  # run profile
  out=$(tuned-adm profile $TUNE_PROFILE 2>&1)
  err=$?
  display "tuned-adm: $out" $LOG_DEBUG
  if (( err != 0 )) ; then
    display "ERROR: tuned-adm error $err" $LOG_FORCE
    exit 50
  fi
}

# install_common: perform node installation steps independent of whether or not
# the node is to be the ambari-server or an ambari-agent.
#
function install_common(){

  # set up /etc/hosts to map ip -> hostname
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

  # copy Ambari repo
  echo
  display "-- Copying Ambari repo file" $LOG_SUMMARY
  copy_ambari_repo

  # install epel
  echo
  display "-- Installing EPEL package" $LOG_SUMMARY
  install_epel
}

# install_storage: perform the installation steps needed when the node is an
#  ambari agent.
#
function install_storage(){

  local i; local out

  # set this node's IP variable
  for (( i=0; i<$NUMNODES; i++ )); do
	[[ $NODE == ${HOSTS[$i]} ]] && break
  done
  IP=${HOST_IPS[$i]}

  # report Gluster version 
  echo
  display "-- Gluster version: $(gluster --version | head -n 1)" $LOG_SUMMARY

  # install Gluster-Hadoop plug-in on agent nodes
  install_plugin

  # install Ambari agent rpm only on agent (data/storage) nodes
  echo
  display "-- Installing Ambari agent" $LOG_SUMMARY
  install_ambari_agent

  # verify FUSE patch on data (agent) nodes, if not installed yum install it.
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
# ambari server.
#
function install_mgmt(){

  echo
  display "-- Installing Ambari server" $LOG_SUMMARY

  # verify java version (note: java not provided by RHS install)
  #NOTE: currently not in use. Using ambari to install correct Java
  #echo
  #display "-- Verifying Java version"
  #verify_java

  install_ambari_server
}


## ** main ** ##
echo
display "$(date). Begin: prep_node" $LOG_REPORT

if [[ ! -d $DEPLOY_DIR ]] ; then
  display "$NODE: Directory '$DEPLOY_DIR' missing on $(hostname)" $LOG_FORCE
  exit -1
fi

cd $DEPLOY_DIR
ls >/dev/null
if (( $? != 0 )) ; then
  display "$NODE: No files found in $DEPLOY_DIR" $LOG_FORCE 
  exit -1
fi

# remove special logfile, start "clean" each time script is invoked
rm -f $PREP_LOG

install_common

[[ $STORAGE_INSTALL == true ]] && install_storage
[[ $MGMT_INSTALL == true    ]] && install_mgmt

display "$(date). End: prep_node" $LOG_REPORT

[[ -n "$REBOOT_REQUIRED" ]] && exit 99 # tell install.sh a reboot is needed
exit 0
#
# end of script
