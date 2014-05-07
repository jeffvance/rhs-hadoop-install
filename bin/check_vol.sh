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
PREFIX="$(dirname $(readlink -f $0))"

# parse cmd opts
while getopts ':q' opt; do
    case "$opt" in
      q)
        QUIET=true # else, undefined
        ;;
      \?) # invalid option
        ;;
    esac
done
shift $((OPTIND-1))

VOLNAME="$1"
[[ -z "$VOLNAME" ]] && {
  echo "Syntax error: volume name is required";
  exit -1; }

[[ -n "$QUIET" ]] && q='-q'

BRKMNTS="$($PREFIX/find_brick_mnts.sh $VOLNAME)"

for brick in $BRKMNTS; do
    node=${brick%:*}
    brkmnt=${brick#*:}
    scp -q -r $PREFIX/../bin $node:/tmp # cp all utility scripts to /tmp/bin
    ssh $node "/tmp/bin/check_node.sh $q $brkmnt" || ((errcnt++))
done

$PREFIX/check_vol_mount.sh $q $VOLNAME $NODES || ((errcnt++))
$PREFIX/check_vol_perf.sh $q $VOLNAME         || ((errcnt++))

(( errcnt > 0 )) && exit 1
[[ -z "$QUIET" ]] && echo "$VOLNAME is ready for hadoop workloads"
exit 0
