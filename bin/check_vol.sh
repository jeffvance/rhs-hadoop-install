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
[[ ${PREFIX##*/} != 'bin' ]] && PREFIX+='/bin'

[[ -z "$QUIET" ]] && q='-q'

NODES="$($PREFIX/find_nodes.sh $VOLNAME)"

for node in $NODES; do
    scp $PREFIX/check_node.sh $node:/tmp
    ssh $node /tmp/check_node.sh $q
done

$PREFIX/check_vol_mount.sh $q $VOLNAME $NODES
(( $? != 0 )) && ((errcnt++))

$PREFIX/check_vol_perf.sh $q $VOLNAME
(( $? != 0 )) && ((errcnt++))

(( errcnt > 0 )) && exit 1
[[ -z "$QUIET" ]] && echo "$VOLNAME is ready for Hadoop workloads"
exit 0
