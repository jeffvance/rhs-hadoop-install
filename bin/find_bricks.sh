#!/bin/bash
#
# find_bricks.sh discovers the bricks for the trusted storage pool, or for the
# given volume if the <volName> arg is supplied. In either case, the list of
# bricks, "<node>:/<brick-mnt-dir>", are output, one brick per line.
# Args:
#   $1=volume name in question. Optional, default is every node in pool.
#   -x=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

PREFIX="$(dirname $(readlink -f $0))"
LOCALHOST="$(hostname)"

source $PREFIX/functions # need vol_exists()

# parse cmd opts
while getopts ':x:' opt; do
    case "$opt" in
      n)
        rhs_node="$OPTARG"
        ;;
      \?) # invalid option
        ;;
    esac
done
shift $((OPTIND-1))

VOLNAME="$1" # optional, default=entire pool
[[ -z "$rhs_node" ]] && rhs_node="$LOCALHOST"

[[ -n "$VOLNAME" ]] && ! vol_exists $VOLNAME $rhs_node && {
  echo "ERROR: volume $VOLNAME does not exist";
  exit 1; }

[[ "$rhs_node" == "$LOCALHOST" ]] && ssh='' || ssh="ssh $rhs_node"

eval "$ssh gluster volume status $VOLNAME | grep -w 'Brick' | awk '{print \$2}'"
(( $? != 0 )) && exit 1
exit 0
