#!/bin/bash
#
# find_nodes.sh discovers the nodes for the trusted storage pool, or for the
# given volume if the <volname> arg is supplied. In either case, the list of
# nodes is output, one node per line.
# Args:
#   $1=volume name in question. Optional, default is every node in pool.
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.
#   -u=output only the unique nodes.

PREFIX="$(dirname $(readlink -f $0))"

# parse cmd opts
while getopts ':un:' opt; do
    case "$opt" in
      n)
        rhs_node="$OPTARG"
        ;;
      u)
        UNIQ=true # else, undefined
        ;;
      \?) # invalid option
        ;;
    esac
done
shift $((OPTIND-1))
VOLNAME="$1" # optional, default=entire pool
[[ -n "$rhs_node" ]] && rhs_node="-n $rhs_node" || rhs_node=''

NODES=($($PREFIX/find_bricks.sh $rhs_node $VOLNAME)) # array
(( $? != 0 )) && {
  echo "${NODES[@]}"; # errmsg from find_bricks
  exit 1; }
  
for (( i=0; i<${#NODES[@]}; i++ )); do
    NODES[$i]="${NODES[$i]%:*}" # just the node name
done

[[ -z "$UNIQ" ]] && {
  echo "${NODES[@]}" | tr ' ' '\n';
  exit 0; }

# unique nodes
echo "$(printf '%s\n' "${NODES[@]}" | sort -u))"
exit 0
