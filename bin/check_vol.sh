#!/bin/bash
#
# check_vol.sh verifies that the supplied volume is setup correctly for hadoop
# workloads. This includes: checking the glusterfs-fuse mount options, the
# block device mount options, the volume performance settings, and executing
# bin/check_node.sh for each node spanned by the volume.
#
# Syntax:
#  $1=volume name
#  -q, if specified, means only set the exit code, do not output anything
#
# Assumption: the node running this script has access to the gluster cli.

errcnt=0; q=''

# parse cmd opts
while getopts ':q' opt; do
    case "$opt" in
      q)
        QUIET=true # else, undefined
        shift
        ;;
      \?) # invalid option
        shift # silently ignore opt
        ;;
    esac
done
VOLNAME="$1"

PREFIX="$(dirname $(readlink -f $0))"
[[ -n "$QUIET" ]] && q='-q'

BRICKS="$($PREFIX/find_bricks.sh $VOLNAME)"

for brick in $BRICKS; do
    node=${brick%:*}
    brkmnt=${brick#*:}
    scp -q $PREFIX/*.sh $node:/tmp # cp all utility scripts to /tmp on node
    ssh $node "/tmp/check_node.sh $q $brkmnt" || ((errcnt++))
done

$PREFIX/check_vol_mount.sh $q $VOLNAME $NODES || ((errcnt++))
$PREFIX/check_vol_perf.sh $q $VOLNAME         || ((errcnt++))

(( errcnt > 0 )) && exit 1
[[ -z "$QUIET" ]] && echo "$VOLNAME is ready for Hadoop workloads"
exit 0
