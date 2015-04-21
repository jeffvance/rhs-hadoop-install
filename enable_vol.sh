#!/bin/bash
#
# enable_vol.sh accepts a volume name, discovers and checks the volume mount on
# each node spanned by the volume to be sure they are setup for hadoop work-
# loads, creates the volume mount on the yarn-master, sets up the storage nodes
# for multi-tenancy, creates additional directories that are needed after 
# Ambari services are started, and updates the Hadoop core-site file to contain
# the volume name and mount. 
#
# If --make-default is specified then the newly enabled volume becomes the
# default hadoop volume, which is used for all unqualified file URIs. This is a
# result of the volname being prepended to the "fs.glusterfs.volumes" property
# value. The default action is to append the target volume to this property
# value, thus not changing the default volume.
#
# NOTE: it is expected that the Ambari install wizard steps have been performed
#   prior to executing this script.
#
# See usage() for syntax.

PREFIX="$(dirname $(readlink -f $0))"

## functions ##

source $PREFIX/bin/functions

# usage: output the general description and syntax.
function usage() {

  cat <<EOF

$ME enables an existing RHS volume for hadoop workloads.

SYNTAX:

$ME --version | --help

$ME [-y] [--quiet | --verbose | --debug] [--make-default] \\
           [--user <ambari-admin-user>] [--pass <ambari-admin-password>] \\
           [--hadoop-mgmt-node <node>] [--rhs-node <node>] \\
           [--yarn-master <node>] <volname>
where:

<volname>    : the RHS volume to be enabled for hadoop workloads.
--yarn-master: (optional) hostname or ip of the yarn-master server which is
               expected to be outside of the storage pool. Default is localhost.
--rhs-node   : (optional) hostname of any of the storage nodes. This is needed
               in order to access the gluster command. Default is localhost
               which, must have gluster cli access.
--hadoop-mgmt-node: (optional) hostname or ip of the hadoop mgmt server which is
               expected to be outside of the storage pool. The port number and
               protocol (http/https) are both omitted. Default is localhost.
--make-default: if specified then the volume is set to be the default volume
               used when hadoop job URIs are unqualified. Default is to NOT 
               make this volume the default volume.
-y           : (optional) auto answer "yes" to all prompts. Default is the 
               script waits for the user to answer each prompt.
--quiet      : (optional) output only basic progress/step messages. Default.
--verbose    : (optional) output --quiet plus more details of each step.
--debug      : (optional) output --verbose plus greater details useful for
               debugging.
--user       : the ambari admin user name. Default: "admin".
--pass       : the password for --user. Default: "admin".
--version    : output only the version string.
--help       : this text.

EOF
}

# parse_cmd: simple positional parsing. Returns 1 on errors.
# Sets globals:
#   ACTION (append or prepend volname to volumes list core-site property)
#   AUTO_YES
#   MGMT_NODE
#   MGMT_PASS
#   MGMT_USER
#   RHS_NODE
#   VERBOSE
#   VOLNAME
#   YARN_NODE
function parse_cmd() {

  local opts='y'
  local long_opts='version,help,make-default,yarn-master:,rhs-node:,hadoop-mgmt-node:,user:,pass:,verbose,quiet,debug'
  local errcnt=0

  # global defaults
  MGMT_PASS='admin'
  MGMT_USER='admin'
  
  eval set -- "$(getopt -o $opts --long $long_opts -- $@)"

  while true; do
      case "$1" in
       --help)
          usage; exit 0
        ;;
        --version) # version is already output, so nothing to do here
          exit 0
        ;;
        --quiet)
          VERBOSE=$LOG_QUIET; shift; continue
        ;;
        --verbose)
          VERBOSE=$LOG_VERBOSE; shift; continue
        ;;
        --debug)
          VERBOSE=$LOG_DEBUG; shift; continue
        ;;
        -y)
          AUTO_YES=1; shift; continue # true
        ;;
        --make-default) # the volname will be prepended to the volumes property
          ACTION='prepend'; shift; continue
        ;;
        --yarn-master)
          YARN_NODE="$2"; shift 2; continue
        ;;
        --rhs-node)
          RHS_NODE="$2"; shift 2; continue
        ;;
        --hadoop-mgmt-node)
          MGMT_NODE="$2"; shift 2; continue
        ;;
        --user)
          MGMT_USER="$2"; shift 2; continue
        ;;
        --pass)
          MGMT_PASS="$2"; shift 2; continue
        ;;
        --)
          shift; break
        ;;
      esac
  done

  VOLNAME="$1"

  # fill in default options
  [[ -z "$ACTION" ]] && ACTION='append' # default: volname is not the default

  # check for required args and options
  [[ -z "$VOLNAME" ]] && {
    echo "Syntax error: volume name is required";
    ((errcnt++)); }

  (( errcnt > 0 )) && return 1

  return 0
}

# get_api_proto_and_port: sets global PROTO and PORT variables from the ambari
# configuration file. If they are missing then defaults are provided. Returns
# 1 for errors, else returns 0.
# Uses globals:
#   MGMT_NODE
#   PREFIX
# Sets globals:
#   PORT
#   PROTO
function get_api_proto_and_port() {

  local out; local ssh=''

  [[ "$MGMT_NODE" == "$HOSTNAME" ]] || ssh="ssh $MGMT_NODE"

  out="$(eval "$ssh $PREFIX/bin/find_proto_and_port.sh")"
  (( $? != 0 )) && {
    err "$out -- on $MGMT_NODE";
    return 1; }
  debug "proto/port= $out"

  PROTO="${out% *}" # global
  PORT=${out#* }    # global
  return 0
}

# show_todo: display values set by the user and discovered by enable_vol.
# Uses globals:
#   ACTION
#   CLUSTER_NAME
#   DEFAULT_VOL
#   MGMT_NODE
#   NODES
#   PORT
#   PROTO
#   VOLMNT
#   VOLNAME
#   YARN_NODE
function show_todo() {

   local msg

  if [[ "$DEFAULT_VOL" == "$VOLNAME" ]] ; then
    msg='will remain the default volume'
  elif [[ -z "$DEFAULT_VOL" || "$ACTION" == 'prepend' ]] ; then
    msg='will become the DEFAULT volume'
  else
    msg='will not be the default volume'
  fi

  echo
  quiet "*** Volume             : $VOLNAME ($msg)"
  [[ -n "$DEFAULT_VOL" ]] && \
    quiet "*** Current default vol: $DEFAULT_VOL"
  quiet "*** Cluster name       : $CLUSTER_NAME"
  quiet "*** Nodes              : $(echo $NODES | sed 's/ /, /g')"
  quiet "*** Volume mount       : $VOLMNT"
  quiet "*** Ambari mgmt node   : $MGMT_NODE"
  quiet "***        proto/port  : $PROTO on port $PORT"
  quiet "*** Yarn-master server : $YARN_NODE"
  echo

}

# setup_yarn_mount: this is the first opportunity to setup the yarn-master
# because we need both the yarn-master node and a volume. Invokes setup_yarn.sh
# script to create the glusterfs-fuse mount for the volume. Returns 1 on
# errors.
# Uses globals:
#   PREFIX
#   RHS_NODE
#   VOLMNT
#   VOLNAME
#   YARN_INSIDE
#   YARN_NODE
function setup_yarn_mount() {

  local out; local err

  (( YARN_INSIDE )) && return 0 # nothing to do

  debug "creating the $VOLNAME mount on $YARN_NODE (yarn-master)..."
  out="$(ssh $YARN_NODE $PREFIX/bin/setup_yarn.sh -n $RHS_NODE \
	$VOLNAME $VOLMNT)"
  err=$?
  if (( err != 0 )) ; then
    err $err "setup_yarn.sh on $YARN_NODE: $out"
    return 1
  fi

  debug "setup_yarn on $YARN_NODE:\n$out"
  debug "created the $VOLNAME mount on $YARN_NODE (yarn-master)"
  return 0
}

# setup_yarn_timeline: sets the yarn timeline dir with the correct owner:group
# and perms. Executed on the yarn node. Returns 1 on errors.
# Uses globals:
#   API_URL
#   CLUSTER_NAME
#   MGMT_*
#   PREFIX
#   YARN_NODE
function setup_yarn_timeline() {

  local out; local dir
  local yarn_owner='yarn:hadoop'; local yarn_perms='0755'
  local yarn_timeline_prop='yarn.timeline-service.leveldb-timeline-store.path'

  debug "set perms on yarn timeline dir on $YARN_NODE (yarn-master)..."

  dir="$($PREFIX/bin/find_prop_value.sh $yarn_timeline_prop yarn \
	$API_URL $MGMT_USER:$MGMT_PASS $CLUSTER_NAME)"
  if (( $? != 0 )) || [[ -z "$dir" ]] ; then
    err "Cannot retrieve yarn dir path therefore cannot chown local yarn dir"
    err "$dir"
    return 1
  fi

  dir="$(dirname $dir)" # save just the left-most dirs in the path
  debug "yarn timeline dir is $dir"

  # chown -R && chmod -R the yarn dir 
  out="$(ssh $YARN_NODE "
	if [[ -d $dir ]] ; then
	  chown -R $yarn_owner $dir 2>&1 && \
  	  chmod -R $yarn_perms $dir 2>&1
          exit
	fi
	echo \"$dir missing on $YARN_NODE\"
        exit 1" )"
  (( $? != 0 )) && {
    err "chown/chmod local yarn dir: $out";
    return 1; }

  debug "chown/chmod local yarn dir \"$dir\" on $YARN_NODE (yarn-master)"
  return 0
}

# chk_nodes: check_vol is called to verify that VOLNAME has been setup for
# hadoop workloads, including each node spanned by the volume. If setup issues
# are detected then, for now, an error is reported and the user needs to re-run
# the setup_cluster script. Later, we may let the user correct issues here.
# Returns 1 for errors.
# Uses globals:
#   LOGFILE
#   PREFIX
#   NODES
#   RHS_NODE
#   VOLNAME
#   YARN_NODE
function chk_nodes() {

  local errcnt=0; local out; local err

  verbose "--- checking that $VOLNAME is setup for hadoop workloads..."

  verify_gid_uids $(uniq_nodes $NODES $YARN_NODE)
  (( $? != 0 )) && ((errcnt++))

  out="$($PREFIX/bin/check_vol.sh -n $RHS_NODE $VOLNAME)"
  err=$?
  if (( err == 1 || err == 2 )) ; then
    if (( err == 1 )) ; then
      ((errcnt++))
      err "issues with 1 or more nodes spanned by $VOLNAME"
      force "A suggestion is to re-run the setup_cluster.sh script to ensure that"
      force "all nodes in the cluster are set up correctly for Hadoop workloads."}
    else
      warn "potential issues with 1 or more nodes spanned by $VOLNAME"
    fi
    force "$out"
    force "See the $LOGFILE log file for additional info."
  else
    debug "check_vol: $out"
  fi

  verbose "--- validate NTP time sync across cluster..."
  out="$(ntp_time_sync_check $(uniq_nodes $NODES $YARN_NODE))"
  if (( $? != 0 )) ; then
    err "$out"
    ((errcnt++))
  else
    debug "ntp time sync check: $out"
  fi
  verbose "--- done validate NTP time sync across cluster"

  (( errcnt > 0 )) && return 1
  verbose "--- nodes spanned by $VOLNAME are ready for hadoop workloads"
  return 0
}

# setup_multi_tenancy: invoke bin/setup_container_executor.sh on each of the 
# passed in nodes (which are expected to be storage nodes).
# Args: $@ = list of storage nodes.
# Uses globals:
#   PREFIX
function setup_multi_tenancy() {

  local node; local out; local err; local errcnt=0

  for node in $@; do
      out="$(ssh $node $PREFIX/bin/setup_container_executor.sh)"
      err=$?
      debug "$node: setup_container_executor, status=$err: $out"
      (( err != 0 )) && ((errcnt++))
  done

  (( errcnt > 0 )) && return 1
  return 0
}

# copy_hcat_files: if the hcat service is enabled then determine which node it
# resides on, and copy select jar/tar files to that node.
# Uses globals:
#   API_URL
#   CLUSTER_NAME
#   MGMT_*
#   PREFIX
#   VOLMNT
function copy_hcat_files() {

  local hcat_node; local warncnt=0; local out
  local src_dir='/usr/share/HDP-webhcat'
  local cp_files="/usr/lib/hadoop-mapreduce/hadoop-streaming-*.jar $src_dir/pig.tar.gz $src_dir/hive.tar.gz"
  local tgt_dir="$VOLMNT/apps/webhcat"
  local owner='hcat:hadoop'; local perms='0755'

  debug "copying webhcat related jar and tar files as needed..."

  # determine which node is running the hcat/webhcat service
  hcat_node="$($PREFIX/bin/find_service_node.sh WEBHCAT WEBHCAT_SERVER \
	$API_URL $MGMT_USER:$MGMT_PASS $CLUSTER_NAME)"
  if (( $? != 0)) || [[ -z "$hcat_node" ]]; then
    debug "cannot find WEBHCAT service node, copy cannot be done: $hcat_node"
    return 0 # not an error
  fi
  debug "webhcat service node is $hcat_node"

  if ! ssh $hcat_node "[[ -d $src_dir ]]" ; then # webhcat not installed
    debug "$src_dir missing on $hcat_node, copy cannot be done"
    return 1
  fi
  
  if ! ssh $hcat_node "[[ -d "$tgt_dir" ]]" ; then
    debug "$tgt_dir target dir missing on $hcat_node, cannot copy post-processing jar and tar files"
    return 0 # not an error
  fi

  out="$(ssh $hcat_node "
	     warncnt=0
	     for f in $cp_files; do
		 echo \"cp \$f $tgt_dir\"
		 cp \$f $tgt_dir 2>&1
		 err=\$?
		 (( err != 0 )) && {
		   ((warncnt++));
		   echo \"warn: copy error: \$err\"; }
	     done
	     echo \"chmod -R $perms $tgt_dir && chown -R $owner $tgt_dir\"
	     chmod -R $perms $tgt_dir && chown -R $owner $tgt_dir
	     err=\$?
	     (( err != 0 )) && {
	       ((warncnt++));
	       echo \"warn: chmod/chown error: \$err\"; }
	     exit \$warncnt
	")"
  warncnt=$?
  debug "on node $hcat_node: copied jar and/or tar files with $warncnt warnings: $out"

  debug "copied webhcat related jar and tar files as needed"
  return 0
}

# post_processing: do all post-ambari install steps. This includes creating 
# the volume mount on the yarn node, creating some distributed dirs, fixing
# owner/perms on other dirs, copying some jar and tar files if the hcat
# service was enabled, setting the yarn timeline dir with the correct owner:
# group and perms. Mostly done on the yarn node. Returns 1 on errors.
# Uses globals:
#   PREFIX
#   RHS_NODE
#   VOLMNT (includes volname)
#   VOLNAME
function post_processing() {

  local err; local ssh; local out

  verbose "--- post-processing for $VOLNAME..."
  [[ "$RHS_NODE" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $RHS_NODE"

  # setup volume mount on yarn node
  setup_yarn_mount || return 1

  # add the required post-processing hadoop dirs
  out="$(eval "$ssh $PREFIX/bin/add_dirs.sh $VOLMNT \
		    $($PREFIX/bin/gen_dirs.sh -p)")"
  err=$?
  debug "add_dirs.sh: $out"
  (( err != 0 )) && return 1

  # set yarn/timeline dir with correct owner and perms
  setup_yarn_timeline || return 1

  # if hcat service is enabled then copy select jar and tar files
  copy_hcat_files || return 1

  verbose "--- end post-processing for $VOLNAME"
  return 0
}

# edit_core_site: invoke bin/set_glusterfs_uri to edit the core-site file and
# restart all ambari services across the cluster. Returns 1 on errors.
# Uses globals:
#   ACTION (append, prepend, or remove volname in core-site)
#   API_URL (omit :port)
#   CLUSTER_NAME
#   MGMT_*
#   PORT
#   PREFIX
#   VOLMNT
#   VOLNAME
function edit_core_site() {

  local mgmt_u; local mgmt_p; local mgmt_port
  local err; local out

  quiet "--- enable $VOLNAME in all core-site.xml files..."

  [[ -n "$MGMT_USER" ]] && mgmt_u="-u $MGMT_USER"
  [[ -n "$MGMT_PASS" ]] && mgmt_p="-p $MGMT_PASS"

  out="$($PREFIX/bin/set_glusterfs_uri.sh -h ${API_URL%:*} $mgmt_u $mgmt_p \
	--port $PORT -c $CLUSTER_NAME --mountpath $VOLMNT --action $ACTION \
	$VOLNAME --debug)"
  err=$?

  if (( err != 0 )) ; then
    err -e $err "set_glusterfs_uri:\n$out"
    return 1
  fi
  debug -e "set_glusterfs_uri:\n$out"

  quiet "--- core-site files modified for $VOLNAME"
  return 0
}


## main ##

ME="$(basename $0 .sh)"
AUTO_YES=0 # false
VERBOSE=$LOG_QUIET # default

report_version $ME $PREFIX

parse_cmd $@ || exit -1

default_nodes MGMT_NODE 'management' YARN_NODE 'yarn-master' \
	RHS_NODE 'RHS storage' || exit -1

# check for passwordless ssh connectivity to rhs_node first
check_ssh $RHS_NODE || exit 1

vol_exists $VOLNAME $RHS_NODE || {
  err "volume $VOLNAME does not exist";
  exit 1; }

# uniq nodes spanned by vol
NODES="$($PREFIX/bin/find_nodes.sh -un $RHS_NODE $VOLNAME)"
(( $? != 0 )) && {
  err "cannot find nodes spanned by $VOLNAME. $NODES";
  exit 1; }
debug "unique nodes spanned by $VOLNAME: $NODES"

# check for passwordless ssh connectivity to all nodes
check_ssh $(uniq_nodes $NODES $YARN_NODE $MGMT_NODE) || exit 1

VOLMNT="$($PREFIX/bin/find_volmnt.sh -n $RHS_NODE $VOLNAME)"  # includes volname
if (( $? != 0 )) ; then
  err "$VOLNAME may not be mounted. $VOLMNT"
  exit 1
fi
debug "$VOLNAME mount point is $VOLMNT"

# get REST api protocol (http vs https) and port #
get_api_proto_and_port || exit 1
API_URL="$PROTO://$MGMT_NODE:$PORT"

CLUSTER_NAME="$($PREFIX/bin/find_cluster_name.sh $API_URL \
	$MGMT_USER:$MGMT_PASS)"
if (( $? != 0 )) ; then
  err "Cannot retrieve cluster name: $CLUSTER_NAME"
  exit 1
fi
debug "Cluster name: $CLUSTER_NAME"

DEFAULT_VOL="$($PREFIX/bin/find_default_vol.sh $API_URL \
	$MGMT_USER:$MGMT_PASS $CLUSTER_NAME)"
if (( $? != 0 )) ; then
  warn "Cannot find configured default volume on node: $DEFAULT_VOL"
  DEFAULT_VOL=''
fi
debug "Default volume: $DEFAULT_VOL"

show_todo

# prompt to continue before any changes are made...
(( ! AUTO_YES )) && ! yesno "Enabling volume $VOLNAME. Continue? [y|N] " && \
  exit 0

# verify nodes spanned by the volume are ready for hadoop workloads, and if
# not prompt user to fix problems.
chk_nodes || exit 1

# set up storage nodes for multi-tennancy
setup_multi_tenancy $NODES || exit 1

# create dirs needed after Ambari services have been started and copy jar files
post_processing || exit 1

# edit the core-site file to recognize the enabled volume
edit_core_site || exit 1

quiet "$VOLNAME enabled for hadoop workloads with no errors"
exit 0
