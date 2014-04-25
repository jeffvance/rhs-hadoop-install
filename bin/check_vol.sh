#!/bin/bash
#
# check_vol.sh verifies that the supplied volume is setup correctly for hadoop
# workloads. This includes: checking the glusterfs-fuse mount options, the
# block device mount options, the volume performance settings, and executing
# bin/check_node.sh for each node spanned by the volume.
#
# Syntax:
#  $1=Volume name
#  -q, if specified, means only set the exit code, do not output anything
#
# Assumption: the node running this script has access to the gluster cli.

quiet=''
errcnt=0

# parse cmd opts
while getopts ':q' opt; do
    case "$opt" in
      q)
        quiet='-q'
        shift
        ;;
      \?) # invalid option
        shift # silently ignore opt
        ;;
    esac
done
VOLNAME="$1"

prefix="$(dirname $(readlink -f $0))"
[[ ${prefix##*/} != 'bin' ]] && prefix+='/bin'

for node in $($prefix/find_nodes.sh $VOLNAME); do
    echo "*** $prefix/check_node.sh $node"
done

$prefix/check_vol_mount.sh $quiet $VOLNAME
(( $? != 0 )) && ((errcnt++))

$prefix/check_vol_perf.sh $quiet $VOLNAME
(( $? != 0 )) && ((errcnt++))

(( errcnt > 0 )) && exit 1

[[ -z "$quiet" ]] && echo "$VOLNAME is ready for Hadoop workloads"
exit 0
