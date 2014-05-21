#!/bin/bash
#
# check_vol.sh verifies that the supplied volume is setup correctly for hadoop
# workloads. This includes: checking the glusterfs-fuse mount options, the
# block device mount options, the volume performance settings, and executing
# bin/check_node.sh for each node spanned by the volume.
#
# Syntax:
#   $1=volume name (required).
#   -y=yarn-master node (required).
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.
#   -q=only set the exit code, do not output anything.

errcnt=0; q=''
PREFIX="$(dirname $(readlink -f $0))"
QUIET=0 # false (meaning not quiet)

# parse cmd opts
while getopts ':qy:n:' opt; do
    case "$opt" in
      n)
        rhs_node="$OPTARG"
        ;;
      y)
        yarn_node="$OPTARG"
        ;;
      q)
        QUIET=1 # true
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

[[ -z "$yarn_node" ]] && {
  echo "Syntax error: yarn-master node is required";
  exit -1; }

(( QUIET )) && q='-q'
[[ -n "$rhs_node" ]] && rhs_node="-n $rhs_node" || rhs_node=''

NODES=''
for brick in $($PREFIX/find_brick_mnts.sh $rhs_node $VOLNAME); do
    node=${brick%:*}; NODES+="$node "
    brkmnt=${brick#*:}
    [[ "$node" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $node"
    eval "$ssh /tmp/bin/check_node.sh $q $brkmnt" || ((errcnt++))
done

$PREFIX/check_vol_mount.sh $q $rhs_node $VOLNAME $NODES || ((errcnt++))
$PREFIX/check_vol_perf.sh $q $rhs_node $VOLNAME || ((errcnt++))
$PREFIX/check_yarn.sh -y $yarn_node $VOLNAME || ((errcnt++))

(( errcnt > 0 )) && exit 1
(( ! QUIET )) && echo "$VOLNAME is ready for hadoop workloads"
exit 0
