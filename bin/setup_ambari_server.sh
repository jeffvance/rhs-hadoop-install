#!/bin/bash
#
# setup_ambari_server.sh: unless the ambari-server is already running, install
# and start the ambari-server on this node (localhost), and set the active flag
# to true in the meta info xml files for all HDP stacks. This causes ambari to
# be aware of alternative HCFS's (hadoop-comptatible-file-systems), such as RHS.
# SELinux is set, to permissive mode. iptables is turned off. Some service HDP
# related directories are remove for unsupported services.
# NOTE: if FORCE_AMBARI is set then even if the server is running it will be re-
#   yum installed and started.
# Syntax:
#  --ambari-repo:  (optional) ambari repo file url.
#  --force-ambari: (optional) if passed then update the agent server even if
#                  it's running.

PREFIX="$(dirname $(readlink -f $0))"
warncnt=0


## functions ##
source $PREFIX/functions

# parse_cmd: use get_opt to parse the command line. Returns 1 on errors.
# Sets globals:
#   AMBARI_REPO
#   FORCE_AMBARI
function parse_cmd() {

  local long_opts='ambari-repo::,force-ambari'

  eval set -- "$(getopt -o'-' --long $long_opts -- $@)"

  while true; do
      case "$1" in
        --ambari-repo) # optional
          shift 2
          [[ "${1:0:2}" == '--' ]] && continue # missing option value
          AMBARI_REPO="$1"; shift; continue
        ;;
        --force-ambari) # optional
          FORCE_AMBARI=1; shift; continue
        ;;
        --)
          shift; break
        ;;
      esac
  done

  # fill in defaults
  [[ -z "$FORCE_AMBARI" ]] && FORCE_AMBARI=0 # false

  return 0
}

# ambari_server: install, start, persist the ambari-server unless it is already
# running (and not overriden by the FORCE_AMBARI flag). "enable" glusterfs by
# setting active=true in all HDP metainfo files. Remove certain HDP services 
# until they are supported by Red Hat.  Returns 1 on errors.
function ambari_server() {

  local AMBARI_SERVER_PID='/var/run/ambari-server/ambari-server.pid'
  local HDP_DIR='/var/lib/ambari-server/resources/stacks/HDP'
  local GLUSTER_DIR='[0-9]*.GlusterFS' # all glusterfs stacks
  local METAINFO_FILE='metainfo.xml'
  local RM_SERVICE_DIRS='FALCON STORM' # dirs to be deleted
  local ACTIVE_FALSE='<active>false<'; ACTIVE_TRUE='<active>true<'
  local dir; local f; local gluster_dirs; local service_dir

  if [[ -f $AMBARI_SERVER_PID ]] && \
     which ambari-server >& /dev/null && \
     ambari-server status >& /dev/null ; then # server is definitely running
    (( ! FORCE_AMBARI )) && {
      echo "ambari-server running, install skipped";
      return 0; } # done
    echo "stopping ambari-server since running in \"FORCE\" mode..."
    ambari-server stop 2>&1
    err=$?
    (( err != 0 )) && {
      echo "WARN $err: couldn't stop ambari server";
      ((warncnt++)); }
    ## Not sure we should reset ambari just because of a "forced" update
    #echo "resetting ambari-server since running in \"FORCE\" mode..."
    #ambari-server reset -s 2>&1
    #err=$?
    #(( err != 0 )) && {
      #echo "WARN $err: couldn't reset ambari server";
      #((warncnt++)); }
  fi

  echo "...wget-ing ambari-server repo..."
  get_ambari_repo $AMBARI_REPO
  err=$?
  (( err != 0 )) && {
    echo "ERROR $err: can't wget ambari repo $AMBARI_REPO";
    return 1; }
  
  echo "...yum installing ambari-server..."
  yum -y install ambari-server 2>&1
  err=$?
  (( err != 0 )) && {
    echo "ERROR $err: ambari server install";
    return 1; }

  # find all HDP GlusterFS stack dirs
  gluster_dirs="$(ls -d $HDP_DIR/$GLUSTER_DIR)"
  echo "...GlusterFS HDP stack directories: $gluster_dirs"

  # delete un-needed service related directories in each glusterfs dir
  # note: must be done after the yum install and before the setup step
  echo "...removing certain service directories until they are supported:"
  echo "...  $RM_SERVICE_DIRS, if present..."
  for dir in $gluster_dirs; do
      for service_dir in $RM_SERVICE_DIRS; do
	 f="$dir/$service_dir" # directory
	 if [[ -d $f ]] ; then
	   echo "...deleting un-needed service directory $f..."
	   rm -rf $f
	   err=$?
	   (( err != 0 )) && {
	     echo "WARN $err: deleting $f directory";
	     ((warncnt++)); }
	 fi
      done
  done

  # note: -s accepts all defaults with no prompting
  echo "...setup ambari-server..."
  ambari-server setup -s 2>&1
  err=$?
  (( err != 0 )) && {
    echo "ERROR $err: ambari server setup";
    return 1; }

  # set the active=true flag in all HDP metainfo xml files so that ambari is
  # aware of alternative HCFS file systems, like RHS/glusterfs.
  echo "...setting \"active\" config flag..."
  for dir in $gluster_dirs; do
     f="$dir/$METAINFO_FILE"
     echo "... in file $f..."
     sed -i -e "s/$ACTIVE_FALSE/$ACTIVE_TRUE/" $f
  done

  echo "...starting ambari-server..."
  ambari-server start 2>&1
  err=$?
  (( err != 0 )) && {
    echo "ERROR $err: ambari-server start";
    return 1; }

  echo "...persisting ambari-server..."
  chkconfig ambari-server on 2>&1
  err=$?
  (( err != 0 )) && {
    echo "WARN $err: chkconfig ambari-server on";
    ((warncnt++)); }

  return 0
}

## main ##

parse_cmd $@ || exit -1

ambari_server || exit 1

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
