#!/bin/bash
#
# setup_ambari_server.sh installs and starts the ambari-server on this node 
# (localhost). The active flag is set to true in the meta info xml file. This
# makes ambari aware of alternative HCFS file systems, like RHS/glusterfs.
# Syntax:
#  -q, if specified, means only set the exit code, do not output anything

PREFIX="$(dirname $(readlink -f $0))"
QUIET=0 # false (meaning not quiet)
warncnt=0
AMBARI_SERVER_PID='/var/run/ambari-server/ambari-server.pid'
METAINFO_PATH='/var/lib/ambari-server/resources/stacks/HDP/2.0.6.GlusterFS/metainfo.xml'
ACTIVE_FALSE='<active>false<'; ACTIVE_TRUE='<active>true<'

# parse cmd opts
while getopts ':q' opt; do
    case "$opt" in
      q)
        QUIET=1 # true
        ;;
      \?) # invalid option
        ;;
    esac
done
shift $((OPTIND-1))

# stop and reset server if running
if [[ -f $AMBARI_SERVER_PID ]] ; then
  out="$(ambari-server stop 2>&1)"
  err=$?
  (( err != 0 )) && { \
    (( ! QUIET )) && echo "WARN $err: couldn't stop ambari server: $out";
    ((warncnt++)); }
  out="$(ambari-server reset -s 2>&1)"
  err=$?
  (( err != 0 )) && { \
    (( ! QUIET )) && echo "WARN $err: couldn't reset ambari server: $out";
    ((warncnt++)); }
fi

# install the ambari server
out="$(yum -y install ambari-server 2>&1)"
err=$?
if (( err != 0 && err != 1 )) ; then # 1--> nothing-to-do
  (( ! QUIET )) && echo "ERROR $err: ambari server install: $out"
  exit 1
fi

# set the active=true flag in the meta info xml file
# aware of alternative HCFS file systems, like RHS/glusterfs.
sed -i -e "s/$ACTIVE_FALSE/$ACTIVE_TRUE/" $METAINFO_PATH

# setup the ambari-server. note: -s accepts all defaults with no prompting
out="$(ambari-server setup -s 2>&1)"
err=$?
if (( err != 0 )) ; then
  (( ! QUIET )) && echo "ERROR $err: ambari server setup: $out"
  exit 1
fi

# start the server now
out="$(ambari-server start 2>&1)"
err=$?
if (( err != 0 )) ; then
  (( ! QUIET )) && echo "ERROR $err: ambari-server start: $out"
  exit 1
fi

# restart the server after a reboot
out="$(chkconfig ambari-server on 2>&1)"
err=$?
(( err != 0 )) && { \
  (( ! QUIET )) && echo "WARN $err: chkconfig ambari-server on: $out";
  ((warncnt++)); }

(( ! QUIET )) && \
  echo "ambari-server installed and running with $warncnt warnings"
exit 0
