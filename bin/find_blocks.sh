#!/bin/bash
#
# find_blocks.sh discovers the blocks devices for the trusted storage pool, or
# for the given volume if the <volName> arg is supplied. In either case, the
# list of "<node>:/<block-devs> are output, one pair per line.
#
# Assumption: the node running this script has access to the gluster cli.

VOLNAME="$1" # optional volume name
PREFIX="$(dirname $(readlink -f $0))"

for brick in $($PREFIX/find_bricks.sh $VOLNAME); do
    node=${brick%:*}
    brickmnt=${brick#*:}    # remove node
    brickmnt=${brickmnt%/*} # remove volname
    ssh $node "
	mnt=\$(grep $brickmnt /proc/mounts)
	echo $node:\${mnt%% *}  # "node:/vg-lv path"
    "
done
