#!/bin/bash
#
# find_nodes.sh discovers the nodes for the trusted storage pool, or for the
# given volume if the <volName> arg is supplied. In either case, the list of
# nodes is output, one node per line.
#
# Assumption: the node running this script has access to the gluster cli.

VOLNAME="$1" # optional volume name
PREFIX="$(dirname $(readlink -f $0))"

for brick in $($PREFIX/find_bricks.sh $VOLNAME); do
    echo "${brick%:*}"
done
