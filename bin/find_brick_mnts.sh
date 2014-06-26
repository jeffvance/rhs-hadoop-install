#!/bin/bash
#
# find_brick_mnts.sh discovers the brick mount dirs for the trusted storage
# pool, or for the given volume if the <volName> arg is supplied. In either
# case, the list of brick-mnts are output, one mount per line. Format:
# "<node>:/<brick-mnt-dir>"
# Syntax:
#   $1=volume name (optional), default='all',
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node,
#   -h=(host) if specified, means only output brick mounts for this host.
#   -x=(no-node) if specified, means only output the brick-mnt portion, omit 
#      each node.

INCL_NODE=1 # true, default
HOST_FILTER='' # don't filter by host
PREFIX="$(dirname $(readlink -f $0))"

# parse cmd opts
while getopts ':xn:h:' opt; do
    case "$opt" in
      n)
        rhs_node="$OPTARG"
        ;;
      x)
        INCL_NODE=0 # false
        ;;
      h)
        HOST_FILTER="$OPTARG"
        ;;
      \?) # invalid option
        ;;
    esac
done
shift $((OPTIND-1))

VOLNAME="$1" # optional volume name
[[ -n "$rhs_node" ]] && rhs_node="-n $rhs_node" || rhs_node=''

BRICKS="$($PREFIX/find_bricks.sh $rhs_node $VOLNAME)"
(( $? != 0 )) && {
  echo "$BRICKS"; # errmsg from find_bricks
  exit 1; }

for brick in $BRICKS; do
    node="${brick%:*}"
    [[ -n "$HOST_FILTER" && "$node" != "$HOST_FILTER" ]] && continue # skip
    (( INCL_NODE )) && echo -n "${node}:"
    brick=${brick%/*} # omit trailing volname
    echo ${brick#*:}  # don't echo node twice
done
