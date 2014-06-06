#!/bin/bash
#
# check_vol.sh verifies that the supplied volume is setup correctly for hadoop
# workloads. This includes: checking the glusterfs-fuse mount options, the
# block device mount options, the volume performance settings, and executing
# bin/check_node.sh for each node spanned by the volume.
#
# Syntax:
#   $1=volume name (required).
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

errcnt=0; q=''
PREFIX="$(dirname $(readlink -f $0))"

# parse cmd opts
while getopts ':n:' opt; do
    case "$opt" in
      n)
        rhs_node="$OPTARG"
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

[[ -n "$rhs_node" ]] && rhs_node="-n $rhs_node" || rhs_node=''

NODES=''
for brick in $($PREFIX/find_brick_mnts.sh $rhs_node $VOLNAME); do
    node=${brick%:*}; NODES+="$node "
    brkmnt=${brick#*:}
    [[ "$node" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $node"
    eval "$ssh /tmp/bin/check_node.sh $brkmnt" || ((errcnt++))
done

$PREFIX/check_vol_mount.sh $rhs_node $VOLNAME $NODES || ((errcnt++))
$PREFIX/check_vol_perf.sh $rhs_node $VOLNAME || ((errcnt++))

(( errcnt > 0 )) && exit 1
echo "$VOLNAME is ready for hadoop workloads"
exit 0
