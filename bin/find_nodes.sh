#!/bin/bash
#
# find_nodes.sh discovers the nodes for the trusted storage pool, or for the
# given volume if the <volName> arg is supplied. In either case, the list of
# nodes is output, one node per line.
#
# Assumption: the node running this script has access to the gluster cli.

VOLNAME="$1" # optional volume name

prefix="$(dirname $(readlink -f $0))"
[[ ${prefix##*/} != 'bin' ]] && prefix+='/bin'

for brick in $($prefix/find_bricks.sh $VOLNAME); do
    echo "${brick%:*}"
done
