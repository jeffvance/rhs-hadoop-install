#!/bin/bash
#
# find_blocks.sh discovers the blocks devices for the trusted storage pool, or
# for the given volume if the <volName> arg is supplied. In either case, the
# list of block-devs are output, one block-dev per line.
#
# Assumption: the node running this script has access to the gluster cli.
#
VOLNAME="$1" # optional volume name

prefix="$(dirname $(readlink -f $0))"
[[ ${prefix##*/} != 'bin' ]] && prefix+='/bin'
bricks="$($prefix/find_bricks.sh $VOLNAME)"

for brick in $bricks; do
    node=${brick%:*}
    brickmnt=${brick#*:}    # remove node
    brickmnt=${brickmnt%/*} # remove volname
    ssh $node "
	mnt=\$(grep $brickmnt /proc/mounts)
	echo \${mnt%% *}  # just vg/lv path
    "
done
