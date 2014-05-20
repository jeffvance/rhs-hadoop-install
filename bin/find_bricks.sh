#!/bin/bash
#
# find_bricks.sh discovers the bricks for the trusted storage pool, or for the
# given volume if the <volName> arg is supplied. In either case, the list of
# bricks, "<node>:/<brick-mnt-dir>", are output, one brick per line.
# REQUIREMENT: at least one volume has to have been created in the pool, even if
#   <volname> is omitted.
# Args:
#   $1=volume name in question. Optional, default is every node in pool.
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

PREFIX="$(dirname $(readlink -f $0))"
LOCALHOST="$(hostname)"

source $PREFIX/functions # need vol_exists()

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

VOLNAME="$1" # optional, default=entire pool
[[ -z "$rhs_node" ]] && rhs_node="$LOCALHOST"

[[ "$rhs_node" == "$LOCALHOST" ]] && ssh='' || ssh="ssh $rhs_node"

eval "$ssh gluster volume status $VOLNAME" >/tmp/volstatus.out
if (( $? != 0 )) ; then
  cat /tmp/volstatus.out
  exit 1
fi

grep -w 'Brick' /tmp/volstatus.out | awk '{print $2}'
exit 0
