#!/bin/bash
#
# setup_ambari_server.sh installs and starts the ambari-server on this node 
# (localhost), and the active flag is set to true in the meta info xml file,
# which makes ambari aware of alternative HCFS file systems, like RHS/glusterfs.
# SELinux is set to permissive mode. iptables is turned off. Some service
# related directories are remove for unsupported services.

PREFIX="$(dirname $(readlink -f $0))"
warncnt=0
AMBARI_SERVER_PID='/var/run/ambari-server/ambari-server.pid'
METAINFO_PATH='/var/lib/ambari-server/resources/stacks/HDP/2.1.GlusterFS/metainfo.xml' # hdp 2.1
ACTIVE_FALSE='<active>false<'; ACTIVE_TRUE='<active>true<'
SERVER_ALREADY_INSTALLED=0 # false
SERVICE_PATH='/var/lib/ambari-server/resources/stacks/HDP/2.1.GlusterFS/services'
RM_SERVICE_DIRS='FALCON STORM' # dirs to be deleted

## functions ##
source $PREFIX/functions

[[ -f $AMBARI_SERVER_PID ]] && ambari-server status && \
  SERVER_ALREADY_INSTALLED=1 # true

# stop ambari-server if running
if (( SERVER_ALREADY_INSTALLED )) ; then
  echo "...stopping ambari-server..."
  ambari-server stop 2>&1
  err=$?
  (( err != 0 )) && {
    echo "WARN $err: couldn't stop ambari server";
    ((warncnt++)); }
fi

echo "...wget-ing ambari-server repo..."
get_ambari_repo
err=$?
(( err != 0 )) && {
  echo "ERROR $err: can't wget ambari repo";
  exit 1; }

echo "...yum installing ambari-server..."
yum -y install ambari-server 2>&1
err=$?
(( err != 0 )) && {
  echo "ERROR $err: ambari server install";
  exit 1; }

# delete un-needed service related directories
# note: must be done after the yum install and before the setup step
for dir in $RM_SERVICE_DIRS; do
    if [[ -f $SERVICE_PATH/$dir ]] ; then
      echo "...deleting un-needed service directory $dir..."
      rm -rf $SERVICE_PATH/$dir
      err=$?
      (( err != 0 )) && {
	echo "WARN $err: deleting $SERVICE_PATH/$dir directory";
	((warncnt++)); }
    fi
done

# note: -s accepts all defaults with no prompting
echo "...setup ambari-server..."
ambari-server setup -s 2>&1
err=$?
(( err != 0 )) && {
  echo "ERROR $err: ambari server setup";
  exit 1; }

# set the active=true flag in the meta info xml file so that ambari is
# aware of alternative HCFS file systems, like RHS/glusterfs.
echo "...set \"active\" config flag..."
sed -i -e "s/$ACTIVE_FALSE/$ACTIVE_TRUE/" $METAINFO_PATH

echo "...starting ambari-server..."
ambari-server start 2>&1
err=$?
(( err != 0 )) && {
  echo "ERROR $err: ambari-server start";
  exit 1; }

echo "...persisting ambari-server..."
chkconfig ambari-server on 2>&1
err=$?
(( err != 0 )) && {
  echo "WARN $err: chkconfig ambari-server on";
  ((warncnt++)); }

echo "...selinux permissive mode..."
setup_selinux
err=$?
(( err != 0 )) && {
  echo "ERROR $err: setting up selinux";
  exit 1; }

echo "...disabling iptables..."
setup_firewall
err=$?
(( err != 0 )) && {
  echo "ERROR $err: disabling iptables";
  exit 1; }

echo "ambari-server installed and running with $warncnt warnings"
exit 0
