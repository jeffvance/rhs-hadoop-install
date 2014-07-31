#!/bin/bash
#
# setup_ambari_server.sh installs and starts the ambari-server on this node 
# (localhost). SELinux is set to permissive mode. The active flag is set to
# true in the meta info xml file, which makes ambari aware of alternative HCFS
# file systems, like RHS/glusterfs.

PREFIX="$(dirname $(readlink -f $0))"
warncnt=0
AMBARI_SERVER_PID='/var/run/ambari-server/ambari-server.pid'
#METAINFO_PATH='/var/lib/ambari-server/resources/stacks/HDP/2.0.6.GlusterFS/metainfo.xml' # hdp 2.0
METAINFO_PATH='/var/lib/ambari-server/resources/stacks/HDP/2.1.GlusterFS/metainfo.xml' # hdp 2.1
ACTIVE_FALSE='<active>false<'; ACTIVE_TRUE='<active>true<'
SERVER_ALREADY_INSTALLED=0 # false

## functions ##
source $PREFIX/functions

[[ -f $AMBARI_SERVER_PID ]] && ambari-server status && \
  SERVER_ALREADY_INSTALLED=1 # true

# stop ambari-server if running
if (( SERVER_ALREADY_INSTALLED )) ; then
  out="$(ambari-server stop 2>&1)"
  err=$?
  (( err != 0 )) && {
    echo "WARN $err: couldn't stop ambari server: $out";
    ((warncnt++)); }

else
  # wget the ambari repo
  get_ambari_repo
  # install the ambari server
  yum -y install ambari-server 2>&1
  err=$?
  (( err != 0 )) && {
    echo "ERROR $err: ambari server install: $out";
    exit 1; }
  # setup the ambari-server. note: -s accepts all defaults with no prompting
  out="$(ambari-server setup -s 2>&1)"
  err=$?
  (( err != 0 )) && {
    echo "ERROR $err: ambari server setup: $out";
    exit 1; }
fi

# set the active=true flag in the meta info xml file
# aware of alternative HCFS file systems, like RHS/glusterfs.
sed -i -e "s/$ACTIVE_FALSE/$ACTIVE_TRUE/" $METAINFO_PATH

# start the server now
ambari-server start 2>&1
err=$?
(( err != 0 )) && {
  echo "ERROR $err: ambari-server start";
  exit 1; }

# restart the server after a reboot
chkconfig ambari-server on 2>&1
err=$?
(( err != 0 )) && {
  echo "WARN $err: chkconfig ambari-server on";
  ((warncnt++)); }

# set selinux to permissive mode
setup_selinux
err=$?
(( err != 0 )) && {
  echo "ERROR $err: setting up selinux";
  exit 1; }

echo "ambari-server installed and running with $warncnt warnings"
exit 0
