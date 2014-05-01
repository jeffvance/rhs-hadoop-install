#!/bin/bash
#
# find_nodes.sh discovers the nodes for the trusted storage pool, or for the
# given volume if the <volName> arg is supplied. In either case, the list of
# nodes is output, one node per line.
#
# Syntax:
#  -u, if specified, means output only the unique nodes.
#
# Assumption: the node running this script has access to the gluster cli.

NODES=()

# parse cmd opts
while getopts ':u' opt; do
    case "$opt" in
      u)
        UNIQ=true # else, undefined
        shift
        ;;
      \?) # invalid option
        shift # silently ignore opt
        ;;
    esac
done

VOLNAME="$1" # optional volume name
PREFIX="$(dirname $(readlink -f $0))"

for brick in $($PREFIX/find_bricks.sh $VOLNAME); do
    NODES+=(${brick%:*})
done

[[ -z "$UNIQ" ]] && {
  echo "${NODES[@]}" | tr ' ' '\n';
  exit; }

echo "$(printf '%s\n' "${NODES[@]}" | sort -u))"
