#!/bin/bash
#
# enable_vol.sh accepts a volume name, discovers and checks the volume mount on
# each node spanned by the volume to be sure they are setup for hadoop work-
# loads, creates the volume mount on the yarn-master, sets up the storage nodes
# for multi-tenancy, and updates the Hadoop core-site file to contain the
# volume. 
# NOTE: it is expected that the Ambari install wizard steps have been performed
#  prior to executing this script.
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

$ME [-y] [--quiet | --verbose | --debug] \\
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
-y           : (optional) auto answer "yes" to all prompts. Default is to answer
               a confirmation prompt.
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
  local long_opts='version,help,yarn-master:,rhs-node:,hadoop-mgmt-node:,user:,pass:,port:,verbose,quiet,debug'
  local errcnt=0

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

  # check for required args and options
  [[ -z "$VOLNAME" ]] && {
    echo "Syntax error: volume name is required";
    ((errcnt++)); }

  return 0
}

# setup_nodes: setup each node for hadoop workloads by invoking
# setup_datanodes.sh. Returns 1 on errors. Assumes all nodes have current
# bin/ scripts in /tmp.
# NOTE: NOT CURRENTY INVOKED BUT MAY BE LATER...
# Uses globals:
#   BLKDEVS
#   BRKMNTS
#   MGMT_NODE
#   NODES
#   VOLNAME
#   YARN_NODE
function setup_nodes() {

  local i=0; local err; local errcnt=0; local out
  local node; local brkmnt; local blkdev; local ssh

  verbose "--- correcting issues on nodes spanned by $VOLNAME..."

  for node in $NODES; do
      brkmnt=${BRKMNTS[$i]}
      blkdev=${BLKDEVS[$i]}

      [[ "$node" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $node"

      out="$(eval "$ssh /tmp/bin/setup_datanode.sh --blkdev $blkdev \
		--brkmnt $brkmnt --hadoop-mgmt-node $MGMT_NODE")"
      err=$?
      if (( err != 0 )) ; then
        err $err "setup_datanode on $node:\n$out"
        ((errcnt++))
      fi
      debug -e "$node: setup_datanode:\n$out"
      ((i++))
  done

  (( errcnt > 0 )) && return 1
  verbose "--- issue(s) corrected"
  return 0
}

# yarn_mount: this is the first opportunity to setup the yarn-master server
# because we need both the yarn-master node and a volume. Invokes setup_yarn.sh
# script. Returns 1 for errors.
# Uses globals:
#   PREFIX
#   RHS_NODE
#   VOLNAME
#   YARN_INSIDE
#   YARN_NODE
function yarn_mount() {

  local out; local err

  (( YARN_INSIDE )) && return 0 # already mounted as a storage node

  verbose "--- setting up the yarn-master: $YARN_NODE..."

  out="$($PREFIX/bin/setup_yarn.sh -n $RHS_NODE -y $YARN_NODE $VOLNAME)"
  err=$?
  if (( err != 0 )) ; then
    err -e $err "setup_yarn on $YARN_NODE:\n$out"
    return 1
  fi

  debug -e "setup_yarn on $YARN_NODE:\n$out"
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
# passed in nodes (which are expected to be storage nodes). Assumes bin/* has
# been copied to /tmp/bin on each node. Returns 1 on errors.
# Args: $@ = list of storage nodes.
function setup_multi_tenancy() {

  local nodes="$@"
  local node; local out; local err; local errcnt=0

  for node in $nodes; do
      out="$(ssh $node /tmp/bin/setup_container_executor.sh)"
      err=$?
      if (( err == 0 )) ; then
	debug "on $node: setup_container_executor: $out"
      else
	((errcnt++))
	err $err "on $node: setup_container_executor: $out"
      fi
  done

  (( errcnt > 0 )) && return 1
  return 0
}

# edit_core_site: invoke bin/set_glusterfs_uri to edit the core-site file and
# restart all ambari services across the cluster. Returns 1 on errors.
# Uses globals:
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
	$mgmt_port --mountpath $VOLMNT $VOLNAME)"
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
errcnt=0
AUTO_YES=0 # false
VERBOSE=$LOG_QUIET # default

quiet '***'
quiet "*** $ME: version $(cat $PREFIX/VERSION)"
quiet '***'
debug "date: $(date)"

parse_cmd $@ || exit -1

default_nodes MGMT_NODE 'management' YARN_NODE 'yarn-master' \
	RHS_NODE 'RHS storage' || exit -1

# check for passwordless ssh connectivity to nodes
check_ssh $(uniq_nodes $MGMT_NODE $YARN_NODE $RHS_NODE) || exit 1

vol_exists $VOLNAME $RHS_NODE || {
  err "volume $VOLNAME does not exist";
  exit 1; }

NODES="$($PREFIX/bin/find_nodes.sh -n $RHS_NODE $VOLNAME)" # spanned by vol
if (( $? != 0 )) ; then
  err "$NODES" # error from find_nodes
  exit 1
fi
debug "nodes spanned by $VOLNAME: $NODES"

VOLMNT="$($PREFIX/bin/find_volmnt.sh -n $RHS_NODE $VOLNAME)"  #includes volname
if (( $? != 0 )) ; then
  err "$VOLMNT" # error from find_volmnt
  exit 1
fi
debug "$VOLNAME mount point is $VOLMNT"

BRKMNTS=($($PREFIX/bin/find_brick_mnts.sh -xn $RHS_NODE $VOLNAME))
BLKDEVS=($($PREFIX/bin/find_blocks.sh -xn $RHS_NODE $VOLNAME))

echo
quiet "*** Volume            : $VOLNAME"
quiet "*** Nodes             : $(echo $NODES        | sed 's/ /, /g')"
quiet "*** Brick mounts      : $(echo ${BRKMNTS[*]} | sed 's/ /, /g')"
quiet "*** Block devices     : $(echo ${BLKDEVS[*]} | sed 's/ /, /g')"
quiet "*** Volume mount      : $VOLMNT"
quiet "*** Ambari mgmt node  : $MGMT_NODE"
quiet "*** Yarn-master server: $YARN_NODE"
echo

# prompt to continue before any changes are made...
(( ! AUTO_YES )) && ! yesno "Enabling volume $VOLNAME. Continue? [y|N] " && \
  exit 0

# setup volume mount on yarn-node
yarn_mount || exit 1

# verify nodes spanned by the volume are ready for hadoop workloads, and if
# not prompt user to fix problems.
chk_nodes || exit 1

# set up storage nodes for multi-tennancy
setup_multi_tenancy $NODES || exit 1

# edit the core-site file to recognize the enabled volume
edit_core_site || exit 1

quiet "$VOLNAME enabled for hadoop workloads with no errors"
exit 0
