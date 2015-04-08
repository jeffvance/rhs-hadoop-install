#!/bin/bash
#
# check_vol.sh verifies that the supplied volume is setup correctly for hadoop
# workloads. This includes: checking the glusterfs-fuse mount options, the
# block device mount options, the volume performance settings, and executing
# bin/check_node.sh for each node spanned by the volume.
# Exit status 1 indicates one or more errors (and possibly warnings).
# Exit status 2 indicates one or more warnings and no errors.
# Exit status 0 indicates no errors or warnings.
#
# Syntax:
#   $1=volume name (required).
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

declare -A BRKMNTS=() # assoc array
errcnt=0; warncnt=0
PREFIX="$(dirname $(readlink -f $0))"

source $PREFIX/functions

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

[[ -n "$rhs_node" ]] && rhs_node="-n $rhs_node"

# collect brick mnts per node (typically 1 brick mnt per node)
for brick in $($PREFIX/find_brick_mnts.sh $rhs_node $VOLNAME); do
    node=${brick%:*}
    brkmnt=${brick#*:}
    BRKMNTS[$node]+="$brkmnt "
done
NODES="${!BRKMNTS[@]}" # unique nodes

# check unique nodes and brick mnts spanned by vol
for node in $NODES; do
    [[ "$node" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $node"
    eval "$ssh $PREFIX/check_node.sh ${BRKMNTS[$node]}" || ((errcnt++))
done

$PREFIX/check_vol_mount.sh $VOLNAME $NODES
rtn=$?
(( rtn == 1 )) && ((errcnt++)) || \
(( rtn == 2 )) && ((warncnt++))

$PREFIX/check_vol_perf.sh $rhs_node $VOLNAME || ((errcnt++))

(( errcnt > 0 )) && exit 1
echo -n "$VOLNAME is ready for hadoop workloads"
(( warncnt > 0 )) && {
  echo -n " with $warncnt warnings";
  echo;
  exit 2; }

echo # flush
exit 0
