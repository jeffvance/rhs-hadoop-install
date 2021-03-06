#!/bin/bash
#
# check_uids.sh verifies that the hadoop users have the same UID across the
# list of passed-in nodes.
# Syntax:
#   $@ = list of nodes expected to contain the hadoop users

PREFIX="$(dirname $(readlink -f $0))"
errcnt=0

NODES=($@)
(( ${#NODES[@]} < 2 )) && {
  echo "Syntax error: a list of 2 or more nodes is required";
  exit -1; }

for u in $($PREFIX/gen_users.sh); do # list of hadoop users
    uids=()
    usr_errcnt=0

    for node in ${NODES[*]} ; do
	[[ "$node" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $node"
	# if user exists extract its UID
	out="$(eval "$ssh getent passwd $u")"
	err=$?
	if (( err != 0 )) ; then
	  ((usr_errcnt++))
	  echo "ERROR $err: user \"$u\" missing on $node: $out"
	  continue
	fi
	out=(${out//:/ }) # array
	out=${out[2]}     # just uid
	# add to uids array
	uids+=($out) # in node order
    done # with all nodes for this user

    (( usr_errcnt > 0 )) && continue # next user, don't check consistency

    # find unique uids
    uniq_uids=($(printf '%s\n' "${uids[@]}" | sort -u))
    if (( ${#uniq_uids[@]} > 1 )) ; then
      ((errcnt++))
      echo -e "\"$u\" user has inconsistent UID across supplied nodes.\n UIDs: ${uniq_uids[*]}"
      for (( i=0; i<${#NODES[@]}; i++ )); do
	  node="${NODES[$i]}"; let fill=(16-${#node})
	  node="$node $(printf ' %.0s' $(seq $fill))" # left-justify
	  echo "       $node has $u UID: ${uids[$i]}"
      done
    fi
done

(( errcnt > 0 || usr_errcnt > 0 )) && exit 1
echo "Consistent UIDs across supplied nodes"
exit 0
