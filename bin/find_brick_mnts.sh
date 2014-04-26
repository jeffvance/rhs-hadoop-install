#!/bin/bash
#
# find_brick_mnts.sh discovers the brick mount dirs for the trusted storage
# pool, or for the given volume if the <volName> arg is supplied. In either
# case, the list of brick-mnts are output, one mount per line.
#
# Assumption: the node running this script has access to the gluster cli.
#
VOLNAME="$1" # optional volume name

prefix="$(dirname $(readlink -f $0))"
[[ ${prefix##*/} != 'bin' ]] && prefix+='/bin'

for brick in $($prefix/find_bricks.sh $VOLNAME); do
    echo "${brick#*:}"
done
