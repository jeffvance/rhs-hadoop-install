#!/bin/bash
#
# find_nodes.sh discovers the nodes for the trusted storage pool, or for the
# given volume if the <volname> arg is supplied. In either case, the list of
# nodes is output, one node per line.
# Args:
#   $1=volume name in question. Optional, default is every node in pool.
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.
#   -u=output only the unique nodes, otherwise, if dup nodes are present they 
#      will all be output.

PREFIX="$(dirname $(readlink -f $0))"
ssh=''; ssh_close=''; rhs_opt=''; UNIQ=0 # false

# parse cmd opts
while getopts ':un:' opt; do
    case "$opt" in
      n)
        rhs_node="$OPTARG"
        ;;
      u)
        UNIQ=1 # true
        ;;
      \?) # invalid option
        ;;
    esac
done
shift $((OPTIND-1))

VOLNAME="$1" # optional, default=entire pool

if [[ -n "$rhs_node" ]] ; then
  ssh="ssh $rhs_node '"; ssh_close="'"
  rhs_node_opt="-n $rhs_node"
fi

if [[ -z "$VOLNAME" ]] ; then # use peer status to get all nodes in pool
  # note: ssh'd-to storage node is not included in peer status
  NODES=($(eval "$ssh
           gluster peer status | grep ^Hostname: | cut -d\" \" -f2 \
	 $ssh_close"))
  err=$?
else # use find_bricks which needs at least one volume created
  NODES=($($PREFIX/find_bricks.sh $rhs_node_opt $VOLNAME))
  err=$?
fi
(( err != 0 )) && {
  echo "${NODES[@]}"; # errmsg from above
  exit 1; }

if [[ -z "$VOLNAME" ]] ; then 
  NODES+=($rhs_node) # since not included in peer status
else
  for (( i=0; i<${#NODES[@]}; i++ )); do
      NODES[$i]="${NODES[$i]%:*}" # just the node name
  done
fi

(( UNIQ )) && echo "$(printf '%s\n' "${NODES[@]}" | sort -u)" || \
  echo "${NODES[*]}" | tr ' ' '\n'

exit 0
