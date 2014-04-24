#!/bin/bash
#
# check_vol.sh verifies that the supplied volume is setup correctly for hadoop
# workloads. This includes: checking the glusterfs-fuse mount options, the
# block device mount options, the volume performance settings, and executing
# bin/check_node.sh for each node spanned by <volName>.
#
# Assumption: the node running this script has access to the gluster cli.
#
#
VOLNAME="$1"

prefix="$(dirname $(readlink -f $0))"
[[ ${prefix##*/} != 'bin' ]] && prefix+='/bin'

for node in $($prefix/find_nodes.sh $VOLNAME); do
    $prefix/check_node.sh $node
done

$prefix/check_vol_mount.sh $VOLNAME
$prefix/check_vol_perf.sh $VOLNAME
