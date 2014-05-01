#!/bin/bash
#
# find_brick_mnts.sh discovers the brick mount dirs for the trusted storage
# pool, or for the given volume if the <volName> arg is supplied. In either
# case, the list of brick-mnts are output, one mount per line. Format:
# "<node>:/<brick-mnt-dir>"
#
# Assumption: the node running this script has access to the gluster cli.

VOLNAME="$1" # optional volume name
PREFIX="$(dirname $(readlink -f $0))"

for brick in $($PREFIX/find_bricks.sh $VOLNAME); do
    echo "${brick%*/}" # "node:/brick-mnt-less-volName"
done
