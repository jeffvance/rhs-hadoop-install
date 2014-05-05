#!/bin/bash
#
# setup_cluster.sh accepts a list of nodes:brick-mnts:block-devs, along with
# the name of the yarn-master and hadoop-mgmt servers, and creates a new trusted
# pool with each node in the node-list being a storage node, while the yarn
# and mgmt nodes are expected to be outside of the pool. On each node the blk-
# device is setup as an xfs file system and mounted to the brick mount dir.
# Each node is also setup for hadoop workloads: ntp config is verified, required
# ports are checked to be open, selinux is set to permissive, etc.
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


## funtions ##

# yesno: prompts $1 to stdin and returns 0 if user answers yes, else returns 1.
# The default (just hitting <enter>) is specified by $2.
# $1=prompt (required),
# $2=default (optional): 'y' or 'n' with 'n' being the default default.
function yesno() {

  local prompt="$1"; local default="${2:-n}" # default is no
  local yn

   while true ; do
       read -p "$prompt" yn
       case $yn in
         [Yy])         return 0;;
         [Yy][Ee][Ss]) return 0;;
         [Nn])         return 1;;
         [Nn][Oo])     return 1;;
         '') # default
           [[ "$default" != 'y' ]] && return 1 || return 0
         ;;
         *) # unexpected...
           echo "Expecting a yes/no response, not \"$yn\""
         ;;
       esac
   done
}

# parse_cmd: use get_opt to parse the command line. Exits on errors.
# Sets globals:
#   YARN_NODE
#   MGMT_NODE
#   AUTO_YES
#   NODE_SPEC
function parse_cmd() {

  local opts='y'
  local long_opts='yarn-master:,hadoop-mgmt-node:'

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

  NODE_SPEC=($@) # array of nodes, brick-mnts, blk-devs -- each separated by ":"
  [[ -z "$NODE_SPEC" || ${#NODE_SPEC[@]} < 2 ]] && {
    echo "Syntax error: expect list of 2 or more nodes plus brick mount(s) and block dev(s)";
    exit -1; }

  [[ -z "$YARN_NODE" || -z "$MGMT_NODE" ]] && {
    echo "Syntax error: both yarn-master and hadoop-mgmt-node are required";
    exit -1; }
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
      node=(${node_spec%%:*}); NODES+=($node)
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

  local brkmnt; local brkmnts; local blkdev
  local node_spec; local i

  # extract the required brick-mnt and blk-dev from the 1st node-spec entry
  node_spec=(${NODE_SPEC[0]//:/ }) # split after subst : with space
  brkmnt=(${node_spec[1]})
  blkdev=(${node_spec[2]})

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


## main ##

BRKMNT=(); BLKDEV=(); NODES=()
PREFIX="$(dirname $(readlink -f $0))"
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
for (( i=0; i<${#NODES[@]}; i++ )); do
    node=${NODES[$i]}
    brkmnt=${BRKMNTS[$i]}
    blkdev=${BLKDEVS[$i]}

    scp -r -q $PREFIX/bin $node:/tmp
    ssh $node "/tmp/bin/setup_datanode.sh -q $blkdev $brkmnt $YARN_NODE"
    err=$?

    if (( err != 0 )) ; then
      errnodes+="$node "
      errcnt++
    fi
done

echo
if (( errcnt > 0 )) ; then
  echo "$errcnt errors on nodes: ${errnodes[@]}"
  exit 1
fi
echo "${#NODES[@]} nodes setup for hadoop workloads with no errors"
exit 0
