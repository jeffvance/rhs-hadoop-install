#!/bin/bash
#
# find_blocks.sh discovers the blocks devices for the trusted storage pool, or
# for the given volume if the <volName> arg is supplied. In either case, the
# list of "<node>:/<block-devs> are output, one pair per line.
# Syntax:
#  $1=volume name
#  -x, (no-node) if specified, means only output the block-devs portion,
#      omit each node.
#
# Assumption: the node running this script has access to the gluster cli.

LOCALHOST=$(hostname)
INCL_NODE=1 # true, default
PREFIX="$(dirname $(readlink -f $0))"

# parse cmd opts
while getopts ':x' opt; do
    case "$opt" in
      n)
        INCL_NODE=0; shift # false
        ;;
      \?) # invalid option
        ;;
    esac
done
VOLNAME="$1" # optional volume name

for brick in $($PREFIX/find_bricks.sh $VOLNAME); do
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
