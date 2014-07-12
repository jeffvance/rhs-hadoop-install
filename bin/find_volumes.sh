#!/bin/bash
#
# find_volumes.sh returns a list of all gluster volumes in the (expected to be)
# existing storage pool.
# Args:
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

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

[[ -n "$1" ]] && {
  echo "Syntax error: no arguments other than -n are expected"
  exit -1; }

if [[ -z "$rhs_node" ]] ; then
  ssh=''; ssh_close=''
else  # use supplied node
  ssh="ssh $rhs_node '"; ssh_close="'"
fi

out="$(eval "$ssh 
	gluster vol status | grep \"^Status of volume:\" | cut -d\" \" -f4
      $ssh_close
")"

[[ -z "$out" ]] && exit 1
echo $out
exit 0
