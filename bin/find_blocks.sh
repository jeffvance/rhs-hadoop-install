#!/bin/bash
#
# find_blocks.sh discovers the blocks devices for the trusted storage pool, or
# for the given volume if the <volName> arg is supplied. In either case, the
# list of "[<node>:]/<block-devs> are output, one pair per line.
# Syntax:
#   $1=volume name in question. Optional, default is every node in pool.
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.
#   -x=(no-node) if specified, means only output the block-devs portion,
#      omit each node.

LOCALHOST=$(hostname)
INCL_NODE=1 # true, default
PREFIX="$(dirname $(readlink -f $0))"

# parse cmd opts
while getopts ':xn:' opt; do
    case "$opt" in
      n)
        rhs_node="$OPTARG"
        ;;
      x)
        INCL_NODE=0 # false
        ;;
      \?) # invalid option
        ;;
    esac
done
shift $((OPTIND-1))

VOLNAME="$1" # optional volume name
[[ -n "$rhs_node" ]] && rhs_node="-n $rhs_node" || rhs_node=''

for brick in $($PREFIX/find_bricks.sh $rhs_node $VOLNAME); do
    node=${brick%:*}
    brickmnt=${brick#*:}    # remove node
    brickmnt=${brickmnt%/*} # remove volname
    [[ "$node" == "$LOCALHOST" ]] && { ssh=''; ssh_close=''; } || \
    				     { ssh="ssh $node '"; ssh_close="'"; }
    eval "$ssh 
	   mnt=\$(grep $brickmnt /proc/mounts)
	   (( $INCL_NODE )) && echo -n $node:
	   echo \${mnt%% *}  # "/vg-lv path"
	  $ssh_close
	"
done
