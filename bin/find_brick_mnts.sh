#!/bin/bash
#
# find_brick_mnts.sh discovers the brick mount dirs for the trusted storage
# pool, or for the given volume if the <volName> arg is supplied. In either
# case, the list of brick-mnts are output, one mount per line. Format:
# "<node>:/<brick-mnt-dir>"
# Syntax:
#  $1=volume name
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.
#   -x=(no-node) if specified, means only output the brick-mnt portion, omit 
#      each node.

INCL_NODE=1 # true, default
PREFIX="$(dirname $(readlink -f $0))"

# parse cmd opts
while getopts ':xn:' opt; do
    case "$opt" in
      n)
        rhs_node="$OPTARG"
        ;;
      x)
        INCL_NODE=0 # false
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
    (( INCL_NODE )) && echo -n "${brick%:*}:" # node:
    brick=${brick%/*} # omit trailing volname
    echo ${brick#*:}  # omit node
done
