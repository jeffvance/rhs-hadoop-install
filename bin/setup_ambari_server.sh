#!/bin/bash
#
# setup_ambari_server.sh installs and starts the ambari-server on this node 
# (localhost). The active flag is set to true in the meta info xml file. This
# makes ambari aware of alternative HCFS file systems, like RHS/glusterfs.

PREFIX="$(dirname $(readlink -f $0))"
warncnt=0
AMBARI_SERVER_PID='/var/run/ambari-server/ambari-server.pid'
METAINFO_PATH='/var/lib/ambari-server/resources/stacks/HDP/2.0.6.GlusterFS/metainfo.xml'
ACTIVE_FALSE='<active>false<'; ACTIVE_TRUE='<active>true<'

## functions ##
source $PREFIX/functions

# wget the ambari repo
get_ambari_repo

# stop and reset server if running
if [[ -f $AMBARI_SERVER_PID ]] ; then
  out="$(ambari-server stop 2>&1)"
  err=$?
  (( err != 0 )) && { \
    echo "WARN $err: couldn't stop ambari server: $out";
    ((warncnt++)); }
  out="$(ambari-server reset -s 2>&1)"
  err=$?
  (( err != 0 )) && { \
    echo "WARN $err: couldn't reset ambari server: $out";
    ((warncnt++)); }
fi

# install the ambari server
yum -y install ambari-server 2>&1
err=$?
if (( err != 0 )) ; then # 1--> nothing-to-do (note sometimes err 1 may be ok?)
  echo "ERROR $err: ambari server install: $out"
  exit 1
fi

# set the active=true flag in the meta info xml file
# aware of alternative HCFS file systems, like RHS/glusterfs.
sed -i -e "s/$ACTIVE_FALSE/$ACTIVE_TRUE/" $METAINFO_PATH

# setup the ambari-server. note: -s accepts all defaults with no prompting
out="$(ambari-server setup -s 2>&1)"
err=$?
if (( err != 0 )) ; then
  echo "ERROR $err: ambari server setup: $out"
  exit 1
fi

# start the server now
out="$(ambari-server start 2>&1)"
err=$?
if (( err != 0 )) ; then
  echo "ERROR $err: ambari-server start: $out"
  exit 1
fi

# restart the server after a reboot
out="$(chkconfig ambari-server on 2>&1)"
err=$?
(( err != 0 )) && { \
  echo "WARN $err: chkconfig ambari-server on: $out";
  ((warncnt++)); }

echo "ambari-server installed and running with $warncnt warnings"
exit 0
