#!/bin/bash
#
# find_brick_mnts.sh discovers the brick mount dirs for the trusted storage
# pool, or for the given volume if the <volName> arg is supplied. In either
# case, the list of brick-mnts are output, one mount per line. Format:
# "<node>:/<brick-mnt-dir>"
# Syntax:
#  $1=volume name
#  -n, (no-node) if specified, means only output the brick-mnt portion,
#      omit each node.
#
# Assumption: the node running this script has access to the gluster cli.

INCL_NODE=1 # true, default
PREFIX="$(dirname $(readlink -f $0))"

# parse cmd opts
while getopts ':n' opt; do
    case "$opt" in
      n)
        INCL_NODE=0; shift # false
        ;;
      \?) # invalid option
        ;;
    esac
done
VOLNAME="$1" # optional volume name

for brick in $($PREFIX/find_bricks.sh $VOLNAME); do
    (( INCL_NODE )) && echo -n "${brick%:*}:" # node:
    brick=${brick%/*} # omit trailing volname
    echo ${brick#*:}  # omit node
done
