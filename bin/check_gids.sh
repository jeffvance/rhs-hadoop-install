#!/bin/bash
#
# check_gids.sh verifies that the hadoop group(s) have the same GID across the
# list of passed-in nodes.
# Syntax:
#   $@ = list of nodes expected to contain the hadoop group(s)

PREFIX="$(dirname $(readlink -f $0))"
errcnt=0; grp_errcnt=0

NODES=($@)
(( ${#NODES[@]} < 2 )) && {
  echo "Syntax error: a list of 2 or more nodes is required";
  exit -1; }

for g in $($PREFIX/gen_groups.sh); do # list of hadoop groups (1 now)
    gids=()
    for node in ${NODES[*]} ; do
	[[ "$node" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $node"
	# if group exists extract its GID
	out="$(eval "$ssh getent group $g")"
	err=$?
	if (( err != 0 )) ; then
	  ((grp_errcnt++))
	  echo "ERROR $err: group \"$g\" missing on $node"
	  continue
	fi

	# extract gid and add to gids array
	gid=${out%:*}  # delete ":users"
	gid=${gid##*:} # extract gid
	gids+=($gid)   # in node order
    done # with all nodes for this group

    (( grp_errcnt > 0 )) && continue # next group, don't check consistency

    # find unique gids
    uniq_gids=($(printf '%s\n' "${gids[@]}" | sort -u))
    if (( ${#uniq_gids[@]} > 1 )) ; then
      ((errcnt++))
      echo -e "\"$g\" group has inconsistent GIDs across supplied nodes.\n GIDs: ${uniq_gids[*]}"
      for (( i=0; i<${#NODES[@]}; i++ )); do
	  node="${NODES[$i]}"; let fill=(16-${#node})
	  node="$node $(printf ' %.0s' $(seq $fill))" # left-justify 
	  echo "       $node has $g GID: ${gids[$i]}"
      done
    fi
done

(( errcnt > 0 || grp_errcnt > 0 )) && exit 1
echo "Consistent GID across supplied nodes"
exit 0
