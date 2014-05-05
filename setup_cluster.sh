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
#
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


## main ##

BRKMNT=(); BLKDEV=()

parse_cmd $@

# parse out list of nodes, format: "node:brick-mnt:blk-dev"
NODES=()
for node_spec in ${NODE_SPEC[@]}; do
    node=(${node_spec%%:*}); NODES+=($node)
    [[ "$node" == "$YARN_NODE" ]] && yarn_inside="$node"
    [[ "$node" == "$MGMT_NODE" ]] && mgmt_inside="$node"
done

# warning if mgmt or yarn-master nodes are inside the storage pool
if [[ -n "$mgmt_inside" || -n "$yarn_inside" ]] ; then
  if [[ -n "$mgmt_inside" && -n "$yarn_inside" ]] ; then
    echo -n "WARN: the yarn-master and hadoop management nodes are inside the storage pool which is sub-optimal."
  elif [[ -n "$mgmt_inside" ]] ; then
    echo -n "WARN: the hadoop management node is inside the storage pool which is sub-optimal."
  else
    echo -n "WARN: the yarn-master node is inside the storage pool which is sub-optimal."
  fi
  if [[ -z "$AUTO_YES" ]] && ! yesno  " Continue? [y|N] " ; then
    exit 0
  fi
fi

# extract the required brick-mnt and blk-dev from the 1st node-spec entry
node_spec=(${NODE_SPEC[0]//:/ }) # split after subst : with space
BRKMNT=(${node_spec[1]})
BLKDEV=(${node_spec[2]})
[[ -z "$BRKMNT" || -z "$BLKDEV" ]] && {
  echo "Syntax error: expect a brick mount and block device to immediately follow the first node (each separated by a \":\")";
  exit -1; }
BRKMNTS+=($BRKMNT); BLKDEVS+=($BLKDEV)

# fill in missing brk-mnts and/or blk-devs
for (( i=1; i<${#NODE_SPEC[@]}; i++ )); do # starting at 2nd entry
    node_spec=${NODE_SPEC[$i]}
    case "$(grep -o ':' <<<"$node_spec" | wc -l)" in # num of ":"s
	0) # brkmnt and blkdev omitted
	   BRKMNTS+=($BRKMNT)
	   BLKDEVS+=($BLKDEV)
           ;;
	1) # only brkmnt specified
	   BLKDEVS+=($BLKDEV)
	   BRKMNTS+=(${node_spec#*:})
           ;;
	2) # either both brkmnt and blkdev specified, or just blkdev specified
	   blkdev="${node_spec##*:}"
	   BLKDEVS+=($blkdev)
	   brkmnts=(${node_spec//:/ }) # array
	   if [[ "${brkmnts[1]}" == "$blkdev" ]] ; then # "::", empty brkmnt
	     BRKMNTS+=($BRKMNT) # default
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

echo
echo "****NODES=${NODES[@]}"
echo "****BRKMNTS=${BRKMNTS[@]}"
echo "****BLKDEVS=${BLKDEVS[@]}"

exit 0
