#!/bin/bash
#
# setup_cluster.sh accepts a list of nodes:brick-mnts:block-devs, along with
# the name of the yarn-master and hadoop-mgmt servers, and creates a new trusted
# pool with each node in the node-list setup as a storage/data node. The yarn
# and mgmt nodes are expected to be outside of the pool, and not to be the same
# server; however these recommendations are not enforced by the script.
#
# On each node the blk-device is setup as an xfs file system and mounted to the
# brick mount dir, ntp config is verified, required gluster & ambari ports are
# checked to be open, selinux is set to permissive, hadoop required users are
# created, and the required hadoop local directories are created (note: the
# required distributed dirs are not created here).

# Also, on all nodes (assumed to be storage- data-nodes) the ambari agent is
# installed (updated if present) and started. The same is also done for the
# hadoop management and yarn-master nodes, unless they are also part of the
# storage pool.
#
# Last, the ambari-server is installed and started on the supplied mgmt-node.
#
# Tasks related to volumes or ambari setup are not done here.
#
# Syntax:
#  -y: auto answer "yes" to any prompts
#  --yarn-master: hostname or ip of the yarn-master server (expected to be out-
#       side of the storage pool)
#  --hadoop-mgmt-node: hostname or ip of the hadoop mgmt server (expected to
#       be outside of the storage pool)
#  node-list: a list of (minimally) 2 nodes, 1 brick mount path and 1 block
#     device path. More generally the node-list looks like:
#     <node1>:<brkmnt1><blkdev1> <node2>[:<brkmnt2>][:<blkmnt2>] ...
#       [<nodeN>][:<brkmntN>][:<blkdevN>]
#     The first <brkmnt> and <blkdev> are required. If all the nodes use the
#     same path to their brick mounts and block devices then there is no need
#     to repeat the brick mount and block dev values. If a node uses a 
#     different brick mount then it is defined following a ":". If a node uses
#     a different block dev the it is defined following two ":" (this assumes
#     that the brick mount is not different). If a node uses both a different
#     brick mount and block dev then each one is proceded by a ":", following
#     the node name.

PREFIX="$(dirname $(readlink -f $0))"


## functions ##

source $PREFIX/yesno

# parse_cmd: use get_opt to parse the command line. Exits on errors.
# Sets globals:
#   AUTO_YES
#   MGMT_NODE
#   NODE_SPEC
#   YARN_NODE
function parse_cmd() {

  local opts='y'
  local long_opts='yarn-master:,hadoop-mgmt-node:'
  local errcnt=0

  eval set -- "$(getopt -o $opts --long $long_opts -- $@)"

  while true; do
      case "$1" in
	-y)
	  AUTO_YES='y'; shift; continue
	;;
	--yarn-master)
	  YARN_NODE="$2"; shift 2; continue
	;;
	--hadoop-mgmt-node)
	  MGMT_NODE="$2"; shift 2; continue
	;;
	--)
	  shift; break
	;;
      esac
  done

  # check required args
  NODE_SPEC=($@) # array of nodes, brick-mnts, blk-devs -- each separated by ":"
  [[ -z "$NODE_SPEC" || ${#NODE_SPEC[@]} < 2 ]] && {
    echo "Syntax error: expect list of 2 or more nodes plus brick mount(s) and block dev(s)";
    ((errcnt++)); }
  [[ -z "$YARN_NODE" || -z "$MGMT_NODE" ]] && {
    echo "Syntax error: both yarn-master and hadoop-mgmt-node are required";
    ((errcnt++)); }

  (( errcnt > 0 )) && exit 1
}

# parse_nodes: set the global NODES array from NODE_SPEC and report warnings
# if the yarn-master or mgmt nodes are inside the storage pool, and prompts
# the user to continue unless AUTO_YES is set. Exits if user answers no.
# Uses globals:
#   NODE_SPEC
#   YARN_NODE
#   MGMT_NODE
# Sets globals:
#   NODES
function parse_nodes() {

  local mgmt_inside; local yarn_inside
  local node_spec; local node

  # parse out list of nodes, format: "node:brick-mnt:blk-dev"
  for node_spec in ${NODE_SPEC[@]}; do
      node=${node_spec%%:*}
      NODES+=($node)
      [[ "$node" == "$YARN_NODE" ]] && yarn_inside="$node"
      [[ "$node" == "$MGMT_NODE" ]] && mgmt_inside="$node"
  done

  # warning if mgmt or yarn-master nodes are inside the storage pool
  if [[ -n "$mgmt_inside" || -n "$yarn_inside" ]] ; then
    if [[ -n "$mgmt_inside" && -n "$yarn_inside" ]] ; then
      echo "WARN: the yarn-master and hadoop management nodes are inside the storage pool which is sub-optimal."
    elif [[ -n "$mgmt_inside" ]] ; then
      echo "WARN: the hadoop management node is inside the storage pool which is sub-optimal."
    else
      echo "WARN: the yarn-master node is inside the storage pool which is sub-optimal."
    fi
    if [[ -z "$AUTO_YES" ]]  && ! yesno  "  Continue? [y|N] " ; then
      exit 0
    fi
  fi

  # warning if yarn-master == mgmt node
  if [[ "$YARN_NODE" == "$MGMT_NODE" ]] ; then
    echo "WARN: the yarn-master and hadoop-mgmt-nodes are the same which is sub-optimal."
    if [[ -z "$AUTO_YES" ]] && ! yesno  "  Continue? [y|N] " ; then
      exit 0
    fi
  fi
}

# parse_brkmnts_and_blkdevs: extracts the brick mounts and block devices from
# the global NODE_SPEC array. Fills in default brkmnts and blkdevs based on
# the values included on the first node (required). Exits on syntax errors.
# Uses globals:
#   NODE_SPEC
# Sets globals:
#   BRKMNTS
#   BLKMNTS
function parse_brkmnts_and_blkdevs() {

  local brkmnts; local i
  # extract the required brick-mnt and blk-dev from the 1st node-spec entry
  local node_spec=(${NODE_SPEC[0]//:/ }) # split after subst : with space
  local brkmnt=${node_spec[1]}
  local blkdev=${node_spec[2]}

  if [[ -z "$brkmnt" || -z "$blkdev" ]] ; then
    echo "Syntax error: expect a brick mount and block device to immediately follow the first node (each separated by a \":\")"
    exit -1
  fi

  BRKMNTS+=($brkmnt); BLKDEVS+=($blkdev) # set globals

  # fill in missing brk-mnts and/or blk-devs
  for (( i=1; i<${#NODE_SPEC[@]}; i++ )); do # starting at 2nd entry
      node_spec=${NODE_SPEC[$i]}
      case "$(grep -o ':' <<<"$node_spec" | wc -l)" in # num of ":"s
	  0) # brkmnt and blkdev omitted
	     BRKMNTS+=($brkmnt)
	     BLKDEVS+=($blkdev)
          ;;
	  1) # only brkmnt specified
	     BLKDEVS+=($blkdev)
	     BRKMNTS+=(${node_spec#*:})
          ;;
	  2) # either both brkmnt and blkdev specified, or just blkdev specified
	     blkdev="${node_spec##*:}"
	     BLKDEVS+=($blkdev)
	     brkmnts=(${node_spec//:/ }) # array
	     if [[ "${brkmnts[1]}" == "$blkdev" ]] ; then # "::", empty brkmnt
	       BRKMNTS+=($brkmnt) # default
	     else
	       BRKMNTS+=(${brkmnts[1]})
	     fi
          ;;
          *) 
	     echo "Syntax error: improperly specified node-list"
	     exit -1
	  ;;
      esac
  done
}

# setup_nodes: setup each node for hadoop workloads by invoking
# bin/setup_datanodes.sh, which is also run for the mgmt-node and for the
# yarn-master node, assuming they are outside of the storage pool.
# Exits on errors.
# Uses globals:
#   BLKDEVS
#   BRKMNTS
#   NODES
#   PREFIX
#   YARN_NODE
function setup_nodes() {

  local i=0; local errcnt=0; local errnodes=''
  local node; local brkmnt; local blkdev
  local do_mgmt=1; local do_yarn=1 # assume both outside pool


  # nested function to call setup_datanodes on a passed-in node, blkdev and
  # brick-mnt.
  function do_node() {

    local node="$1"; local blkdev="$2"; local brkmnt="$3"

    scp -r -q $PREFIX/bin $node:/tmp
    ssh $node "/tmp/bin/setup_datanode.sh --blkdev $blkdev --brkmnt $brkmnt \
	--yarn-master $YARN_NODE --hadoop-mgmt-node $MGMT_NODE"
    (( $? != 0 )) && return 1
    return 0
  }

  # main #
  for node in ${NODES[@]}; do
      brkmnt=${BRKMNTS[$i]}
      blkdev=${BLKDEVS[$i]}

      do_node "$node" "$blkdev" "$brkmnt" || {
	  errnodes+="$node ";
	  ((errcnt++)); }
      [[ "$node" == "$MGMT_NODE" ]] && do_mgmt=0 # false
      [[ "$node" == "$YARN_NODE" ]] && do_yarn=0 # false
      ((i++))
  done

  if (( do_mgmt )) ; then
    do_node $MGMT_NODE || ((errcnt++)) # blkdev and brkmnt are blank
  fi
  if (( do_yarn )) ; then
    do_node $YARN_NODE || ((errcnt++)) # blkdev and brkmnt are blank
  fi

  if (( errcnt > 0 )) ; then
    echo "$errcnt setup node errors on nodes: $errnodes"
    exit 1
  fi
}

# create_pool: create the trusted pool, even if the pool already exists.
# Note: gluster peer probe returns 0 if the node is already in the pool. It
#   returns 1 if the node is unknown.
# Note: not needed to probe "yourself" but not an error either, and this way we
#   don't need to know which storage node this script is being executed from
function create_pool() {

  local node; local err; local errcnt=0; local errnodes=''

  for node in ${NODES[@]}; do
      gluster peer probe $node >& /dev/null
      err=$?
      if (( err != 0 )) ; then
	echo "ERROR $err: peer probe failed on $node"
	errnodes+="$node "
	((errcnt++))
      fi
  done

  if (( errcnt > 0 )) ; then
    echo "$errcnt peer probe errors on nodes: $errnodes"
    exit 1
  fi
}


## main ##

BRKMNTS=(); BLKDEVS=(); NODES=()
errnodes=''; errcnt=0

parse_cmd $@

parse_nodes

parse_brkmnts_and_blkdevs

echo
echo "****NODES=${NODES[@]}"
echo "****BRKMNTS=${BRKMNTS[@]}"
echo "****BLKDEVS=${BLKDEVS[@]}"
echo

# setup each node for hadoop workloads
setup_nodes

# create the trusted storage pool
create_pool

# install and start the ambari server on the MGMT_NODE
scp -r -q $PREFIX/bin $MGMT_NODE:/tmp
ssh $MGMT_NODE "/tmp/bin/setup_ambari_server.sh 

echo "${#NODES[@]} nodes setup for hadoop workloads with no errors"
exit 0
