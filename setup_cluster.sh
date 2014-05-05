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

BRKMNT=(); BLKDEV=()
opts='yarn-master:,hadoop-mgmt-node:'

# parse cmd opts
eval set -- "$(getopt -o '' --long $opts -- $@)"

while true; do
    case "$1" in
      --yarn-master)
	YARN_NODE="$2"; shift
	;;
      --hadoop-mgmt-node)
	MGMT_NODE="$2"; shift
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

# parse out list of nodes, format: "node:brick-mnt:blk-dev"
NODES=''
for node_spec in ${NODE_SPEC[@]}; do
    NODES+="${node_spec%%:*} "
done

# extract the required brick-mnt and blk-dev from the 1st node-spec entry
node_spec=(${NODE_SPEC[0]//:/ }) # split after subst : with space
BRKMNT=(${node_spec[1]})
BLKDEV=(${node_spec[2]})
[[ -z "$brkmnt" || -z "$blkdev" ]] &&
  echo "Syntax error: expect a brick mount and block device to immediately follw the first node (each separated by a \":\"";
  exit -1; }
BRKMNTS+=($brkmnt); BLKDEVS+=($blkdev)

# fill in missing brk-mnts and/or blk-devs
for (( i=1; i<${#NODE_SPEC[@]}; i++ )); do # starting at 2nd entry
    node_spec=${NODE_SPEC[$i]}
    case $(grep -o ':' <<<$node_spec | grep -c) in # num of ":"s
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
	   if [[ "${brkmnts[1]}" == "${blkdev}" ]] ; then # "::", empty brkmnt
	     BRKMNTS+=($BRKMNT) # default
	   else
	     BRKMNTS+=(${brkmnts[1]})
	   fi
           ;;
        *) 
	   echo "Syntax error: improperly specified node-list"
	   exit -1
	   ;;;
    esac
done


exit 0
