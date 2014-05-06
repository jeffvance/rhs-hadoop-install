#!/bin/bash
#
# create_vol.sh accepts a volume name, volume mount path prefix, and a list of
# two or more "node:brick_mnt" pairs and creates a new volume. Each node spanned
# by the new volume is setup for hadoop workloads and some volume settings are
# set needed for hadoop tasks. The volume is mounted with the correct glusterfs-
# fuse mount options.
# Syntax:
#  volName: name of the new volume
#  vol-mnt-prefix: path of the glusterfs-fuse mount point, eg. /mnt/glusterfs.
#     Note: the volume name will be appended to this mount point.
#  node-list: a list of (minimally) 2 nodes and 1 brick mount path. For example
#     "create_vol.sh HadoopVol /mnt/glusterfs rhs21-1:/mnt/brick1 rhs21-2" the
#     glusterfs-fuse mount on node rhs21-1 will be "/mnt/glusterfs/HadoopVol".
#     The general syntax is: <node1>:<brkmnt1> <node1>[:<brkmnt2>] ... 
#       <nodeN>[:<brkmntN>]
#     The first <brkmnt> is required. If all the nodes use the same path to
#     their brick mounts then there is no need to repeat the brick mount point.
#     If a node uses a different brick mount then it is defined following a
#     ":" after the node name.
#
# Assumption: script must be executed from a node that has access to the 
#  gluster cli.

## funtions ##

# parse_cmd: simple positional parsing. Exits on errors.
# Sets globals:
#   VOLNAME
#   VOLMNT
#   NODE_SPEC (node:brkmnt)
function parse_cmd() {

  VOLNAME="$1"; shift
  VOLMNT="$1"; shift
  NODE_SPEC=($@) # array of nodes:brick-mnts.

  [[ -z "$VOLNAME" ]] && {
    echo "Syntax error: volume name is required";
    exit -1; }
  [[ -z "$VOLMNT" ]] && {
    echo "Syntax error: volume mount path prefix is required";
    exit -1; }
  [[ -z "$NODE_SPEC" || ${#NODE_SPEC[@]} < 2 ]] && {
    echo "Syntax error: expect list of 2 or more nodes plus brick mount(s)";
    exit -1; }
}

# parse_nodes: set the global NODES array from NODE_SPEC.
# Uses globals:
#   NODE_SPEC
# Sets globals:
#   NODES
function parse_nodes() {

  local node_spec

  # parse out list of nodes, format: "node:brick-mnt"
  for node_spec in ${NODE_SPEC[@]}; do
      NODES+=(${node_spec%%:*})
  done
}

# parse_brkmnts: extracts the brick mounts from the global NODE_SPEC array.
# Fills in default brkmnts based on the values included on the first node
# (required). Exits on syntax errors.
# Uses globals:
#   NODE_SPEC
# Sets globals:
#   BRKMNTS
function parse_brkmnts() {

  local brkmnt; local brkmnts
  local node_spec; local i

  # extract the required brick-mnt from the 1st node-spec entry
  brkmnt=${NODE_SPEC[0]%:*}

  if [[ -z "$brkmnt" ]] ; then
    echo "Syntax error: expect a brick mount, preceded by a \":\", to immediately follow the first node"
    exit -1
  fi

  BRKMNTS+=($brkmnt) # set global

  # fill in missing brk-mnts
  for (( i=1; i<${#NODE_SPEC[@]}; i++ )); do # starting at 2nd entry
      node_spec=${NODE_SPEC[$i]}
      case "$(grep -o ':' <<<"$node_spec" | wc -l)" in # num of ":"s
	  0) # brkmnt omitted
	     BRKMNTS+=($brkmnt) # default
          ;;
	  1) # brkmnt specified
	     BRKMNTS+=(${node_spec#*:})
          ;;
          *) 
	     echo "Syntax error: improperly specified node-list"
	     exit -1
	  ;;
      esac
  done
}

# chk_vol: invokes gluster vol status to see if VOLNAME already exists. Exists
# on errors.
# Uses globals:
#   VOLNAME
function chk_vol() {

  local err

  gluster volume status $VOLNAME >& /dev/null
  err=$?
  if (( err == 0 )) ; then
    echo "ERROR: volume $VOLNAME already exists"
    exit 1
  fi
}

# chk_nodes: verify that each node that will be spanned by the new volume is 
# prepped for hadoop workloads by invoking bin/check_node.sh.
# Uses globals:
#   NODES
#   BRKMNTS
#   PREFIX
# Side effect: all scripts under bin/ are copied to each node.
function chk_nodes() {

  local i; local node
  local err; local errcnt=0; local errnodes=''

  # verify that each node is prepped for hadoop workloads
  for (( i=0; i<${#NODES[@]}; i++ )); do
      node=${NODES[$i]}
      scp -r -q $PREFIX/bin $node:/tmp
      ssh $node "/tmp/bin/check_node.sh ${BRKMNTS[$i]}"
      err=$?
      if (( err != 0 )) ; then
        errnodes+="$node "
        errcnt++
      fi
  done

  if (( errcnt > 0 )) ; then
    echo "$errcnt errors on nodes: $errnodes"
    exit 1
  fi
  echo "${#NODES[@]} passed check for hadoop workloads"
}


## main ##

BRKMNT=(); NODES=()
PREFIX="$(dirname $(readlink -f $0))"
bricks=''; errcnt=0

parse_cmd $@

parse_nodes

parse_brkmnts

# make sure the volume doesn't already exist
chk_vol

echo
echo "****NODES=${NODES[@]}"
echo "****BRKMNTS=${BRKMNTS[@]}"
echo

# verify that each node is prepped for hadoop workloads
chk_nodes

# add distrib dirs per node
# create gluster vol mount, per node

# create the gluster volume, replica 2 is hard-coded for now
for (( i=0; i<${#NODES[@]}; i++ )); do
    bricks+="${NODES[$i]}:${BRKMNTS[$i]} "
done
gluster volume create $VOLNAME replica 2 $bricks

# set vol performance settings
$PREFIX/bin/set_vol_perf.sh $VOLNAME

exit 0
