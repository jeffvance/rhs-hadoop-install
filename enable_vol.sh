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
           [--port <port-num>] [--hadoop-mgmt-node <node>] \\
           [--rhs-node <node>] [--yarn-master <node>] \\
           <volname>
where:

<volname>    : the RHS volume to be enabled for hadoop workloads.
--yarn-master: (optional) hostname or ip of the yarn-master server which is
               expected to be outside of the storage pool. Default is localhost.
--rhs-node   : (optional) hostname of any of the storage nodes. This is needed
               in order to access the gluster command. Default is localhost
               which, must have gluster cli access.
--hadoop-mgmt-node: (optional) hostname or ip of the hadoop mgmt server which is
               expected to be outside of the storage pool. Default is localhost.
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
--port       : the port number used by the ambari server. Default: 8080.
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
#   MGMT_PORT
#   MGMT_USER
#   RHS_NODE
#   VERBOSE
#   VOLNAME
#   YARN_NODE
function parse_cmd() {

  local opts='y'
  local long_opts='version,help,make-default,yarn-master:,rhs-node:,hadoop-mgmt-node:,user:,pass:,port:,verbose,quiet,debug'
  local errcnt=0

  # global defaults
  MGMT_PASS='admin'
  MGMT_PORT=8080
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
        --port)
          MGMT_PORT="$2"; shift 2; continue
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

# show_todo: display values set by the user and discovered by enable_vol.
# Uses globals:
#   ACTION
#   CLUSTER_NAME
#   DEFAULT_VOL
#   MGMT_NODE
#   NODES
#   VOLMNT
#   VOLNAME
#   YARN_NODE
function show_todo() {

   local msg

  if [[ "$DEFAULT_VOL" == "$VOLNAME" ]] ; then
    msg="will remain the default volume"
  elif [[ -z "$DEFAULT_VOL" || "$ACTION" == 'prepend' ]] ; then
    msg="will become the DEFAULT volume"
  else
    msg="will not be the default volume"
  fi

  echo
  quiet "*** Volume             : $VOLNAME ($msg)"
  [[ -n "$DEFAULT_VOL" ]] && \
    quiet "*** Current default vol: $DEFAULT_VOL"
  quiet "*** Cluster name       : $CLUSTER_NAME"
  quiet "*** Nodes              : $(echo $NODES | sed 's/ /, /g')"
  quiet "*** Volume mount       : $VOLMNT"
  quiet "*** Ambari mgmt node   : $MGMT_NODE"
  quiet "*** Yarn-master server : $YARN_NODE"
  echo

}

# setup_yarn: this is the first opportunity to setup the yarn-master server
# because we need both the yarn-master node and a volume. Invokes setup_yarn.sh
# script to create the glusterfs-fuse mount for the volume. Also, the yarn/
# timeline dir is set with the correct owner:group and perms. Returns 1 on
# errors.
# Uses globals:
#   CLUSTER_NAME
#   MGMT_*
#   PREFIX
#   RHS_NODE
#   VOLNAME
#   YARN_INSIDE
#   YARN_NODE
function setup_yarn() {

  local out; local err; local dir_prefix
  local dirs='yarn:0755:yarn yarn/timeline:0755:yarn' "<dir>:<perm>:<owner>"
  local yarn_timeline_prop='yarn.timeline-service.leveldb-timeline-store.path'
  local dir_filter='/yarn/timeline/leveldb-timeline-store.ldb'

  if (( ! YARN_INSIDE )) ; then # yarn node is not a rhs node, so need vol mnt
    verbose "--- setting up the yarn-master: $YARN_NODE..."
    out="$(ssh $YARN_NODE $PREFIX/bin/setup_yarn.sh -n $RHS_NODE $VOLNAME)"
    err=$?
    if (( err != 0 )) ; then
      err $err "setup_yarn on $YARN_NODE: $out"
      return 1
    fi
    debug -e "setup_yarn on $YARN_NODE:\n$out"
  fi

  # set yarn/timeline dir with correct owner and perms
  debug "update yarn local directories on $MGMT_NODE (yarn-master)..."

  dir_prefix="$($PREFIX/bin/find_prop_value.sh $prop yarn \
	$MGMT_NODE:$MGMT_PORT $MGMT_USER:$MGMT_PASS $CLUSTER_NAME)"
  if (( $? != 0 )) || [[ -z "$dir_prefix" ]] ; then
    err "Cannot retrieve yarn dir path therefore cannot chown yarn timline dir"
    err "$dir_prefix"
    return 1
  fi
  # save just the left-most dirs in the path
  dir_prefix="${dir_prefix%$dir_filter}"

  # add dirs (if needed) and chown && chmod the dirs
  out="$(ssh $YARN_NODE $PREFIX/bin/add_dirs.sh $dir_prefix $dirs)"
  (( $? != 0 )) && {
    err "updating local yarn-specific dirs \"$dirs\": $out";
    return 1; }
  debug "updated yarn local directories on $MGMT_NODE (yarn-master)"

  verbose "--- done setting up the yarn-master"
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
function chk_nodes() {

  local errcnt=0; local out; local err

  verify_gid_uids $NODES $YARN_NODE 
  (( $? != 0 )) && ((errcnt+))

  verbose "--- checking that $VOLNAME is setup for hadoop workloads..."

  out="$($PREFIX/bin/check_vol.sh -n $RHS_NODE $VOLNAME)"
  err=$?
  debug "check_vol: $out"
  if (( err != 0 )) ; then # 1 or more issues detected on volume
    ((errcnt++))
    err "issues with 1 or more nodes spanned by $VOLNAME"
    debug "Nodes spanned by $VOLNAME: $NODES"
    force "A suggestion is to re-run the setup_cluster.sh script to ensure that"
    force "all nodes in the cluster are set up correctly for Hadoop workloads."
    force "See the $LOGFILE log file for additional info."
  fi

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

  local nodes="$@"
  local node; local out; local err; local errcnt=0

  for node in $nodes; do
      out="$(ssh $node $PREFIX/bin/setup_container_executor.sh)"
      err=$?
      debug "$node: setup_container_executor, status=$err: $out"
      (( err != 0 )) && ((errcnt++))
  done

  (( errcnt > 0 )) && return 1
  return 0
}

# post_processing: create the distributed hadoop directories that need to be
# added after the Ambari services have been started, and copy some jar files.
# Returns 1 on errors.
# Uses globals:
#   PREFIX
#   RHS_NODE
#   VOLMNT (includes volname)
#   VOLNAME
function post_processing() {

  local err; local ssh; local out; local f; local warncnt=0
  local src_dir='/usr/share/HDP-webhcat'
  local cp_files="/usr/lib/hadoop-mapreduce/hadoop-streaming-*.jar $src_dir/pig.tar.gz $src_dir/hive.tar.gz"
  local tgt_dir="$VOLMNT/apps/webhcat"

  verbose "--- adding post-processing hadoop directories for $VOLNAME..."
  [[ "$RHS_NODE" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $RHS_NODE"

  # add the required post-processing hadoop dirs
  out="$(eval "$ssh $PREFIX/bin/add_dirs.sh $VOLMNT \
		$($PREFIX/bin/gen_dirs.sh -p)")"
  err=$?
  if (( err != 0 )) ; then
    err $err "could not add required hadoop dirs: $out"
    return 1
  fi
  debug "add_dirs -p $VOLMNT: $out"
  verbose "--- added post-processing hadoop directories for $VOLNAME"

  # now copy select jar and tar files
  if [[ ! -d "$src_dir" ]] ; then # webhcat not installed, so we're done
    debug "$src_dir missing, service not installed, no copy needed"
    return 0
  fi
  
  verbose "--- copying jar and tar files as needed..."
  [[ ! -d "$tgt_dir" ]] && {
    err "$tgt_dir target dir missing, cannot copy post-processing jar files";
    return 1; }

  for f in $cp_files; do
      debug "cp $f $tgt_dir"
      out="$(cp $f $tgt_dir 2>&1)"
      err=$?
      (( err != 0 )) && {
	((warncnt++));
	debug "warn: cp error $err: $out"; }
  done

  verbose "--- copied jar files with $warncnt warnings"
  return 0
}

# edit_core_site: invoke bin/set_glusterfs_uri to edit the core-site file and
# restart all ambari services across the cluster. Returns 1 on errors.
# Uses globals:
#   ACTION (append, prepend, or remove volname in core-site)
#   CLUSTER_NAME
#   MGMT_*
#   PREFIX
#   VOLMNT
#   VOLNAME
function edit_core_site() {

  local mgmt_u; local mgmt_p; local mgmt_port
  local err; local out

  verbose "--- enable $VOLNAME in all core-site.xml files..."

  [[ -n "$MGMT_USER" ]] && mgmt_u="-u $MGMT_USER"
  [[ -n "$MGMT_PASS" ]] && mgmt_p="-p $MGMT_PASS"
  [[ -n "$MGMT_PORT" ]] && mgmt_port="--port $MGMT_PORT"

  out="$($PREFIX/bin/set_glusterfs_uri.sh -h $MGMT_NODE $mgmt_u $mgmt_p \
	$mgmt_port -c $CLUSTER_NAME --mountpath $VOLMNT --action $ACTION \
	$VOLNAME --debug)"
  err=$?

  if (( err != 0 )) ; then
    err -e $err "set_glusterfs_uri:\n$out"
    return 1
  fi
  debug -e "set_glusterfs_uri:\n$out"

  verbose "--- core-site files modified for $VOLNAME"
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

NODES="$($PREFIX/bin/find_nodes.sh -n $RHS_NODE $VOLNAME)" # spanned by vol
if (( $? != 0 )) ; then
  err "cannot find nodes spanned by $VOLNAME. $NODES"
  exit 1
fi
debug "nodes spanned by $VOLNAME: $NODES"

# check for passwordless ssh connectivity to all nodes
check_ssh $(uniq_nodes $MGMT_NODE $YARN_NODE $NODES) || exit 1

VOLMNT="$($PREFIX/bin/find_volmnt.sh -n $RHS_NODE $VOLNAME)"  #includes volname
if (( $? != 0 )) ; then
  err "$VOLNAME may not be mounted. $VOLMNT"
  exit 1
fi
debug "$VOLNAME mount point is $VOLMNT"

DEFAULT_VOL="$($PREFIX/bin/find_default_vol.sh -n $RHS_NODE)"
(( $? != 0 )) && {
  warn "Cannot find configured default volume on node: $DEFAULT_VOL";
  DEFAULT_VOL=''; }
debug "Default volume: $DEFAULT_VOL"

CLUSTER_NAME="$($PREFIX/bin/find_cluster_name.sh $MGMT_NODE:$MGMT_PORT \
	$MGMT_USER:$MGMT_PASS)"
if (( $? != 0 )) ; then
  err "Cannot retrieve cluster name: $CLUSTER_NAME"
  exit 1
fi
debug "Cluster name: $CLUSTER_NAME"

show_todo

# prompt to continue before any changes are made...
(( ! AUTO_YES )) && ! yesno "Enabling volume $VOLNAME. Continue? [y|N] " && \
  exit 0

# do post-ambari install setup on the yarn node
setup_yarn || exit 1

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
