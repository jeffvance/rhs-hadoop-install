#!/bin/bash
#
# find_volmnt.sh discovers the gluster volume mount directory for the passed in
# volume (required). A single line containing just the "vol-mnt" is output. Eg.
# "/mnt/glusterfs/HadoopVol".
# Args:
#   $1=volume name (required).
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

PREFIX="$(dirname $(readlink -f $0))"

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

mnt=($($PREFIX/find_mount.sh --live --vol --filter $VOLNAME $rhs_node))

[[ -z "$mnt" ]] || (( ${#mnt[@]} < 2 )) && exit 1

echo ${mnt[1]} # /vol-mount-path
exit 0
