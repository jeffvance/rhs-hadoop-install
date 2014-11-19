#!/bin/bash
#
# find_volmnt.sh discovers the gluster volume mount directory for the passed in
# volume (required). A single line containing just the "vol-mnt" is output. Eg.
# "/mnt/glusterfs/HadoopVol".
# Args:
#   $1=volume name (required).
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
VOLNAME="$1"
[[ -z "$VOLNAME" ]] && {
  echo "Syntax error: volume name is required";
  exit -1; }

if [[ -z "$rhs_node" ]] ; then
  ssh=''; ssh_close='' # assume localhost
else  # use supplied node
  ssh="ssh $rhs_node '"; ssh_close="'"
fi

out="$(eval "$ssh 
	mnt=(\$(grep -E ":/$VOLNAME\s+.*\s+fuse.glusterfs\s" /proc/mounts)) #arry
	echo \${mnt[1]} # /vol-mount-path
      $ssh_close
")"

[[ -z "$out" ]] && exit 1
echo $out
exit 0
