#!/bin/bash
#
# find_bricks.sh outputs the bricks for the passed-in volume formatted as:
# "<node>:/<brick-mnt-dir>", one brick per line. Note that the brick-mnt-dir
# includes the volume name.
#
# Note: "detail" is required in gluster vol status command since the standard
#   output splits its output in the middle of the hostname when the hostname is
#   long.
# Args:
#   $1=(required) volume name,
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

tmpfile='/tmp/volstatus.out'

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
  echo "Syntax error: volume is required"; exit -1; }

[[ -z "$rhs_node" ]] && rhs_node="$HOSTNAME"

[[ "$rhs_node" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $rhs_node"

eval "$ssh gluster volume status $VOLNAME detail 2>&1" >$tmpfile
if (( $? != 0 )) ; then
  cat $tmpfile # show error text
  exit 1
fi
grep -w 'Brick' $tmpfile | awk '{print $4}'
exit

### Note: if we later need to add back --xml to gluster vol status then the
###   code below works:
#
#eval "$ssh 'gluster --xml volume status $VOLNAME >$tmpfile 2>&1'"
#if (( $? != 0 )) ; then
  #eval "$ssh cat $tmpfile" # show error text
  #exit 1
#fi
#
# get the num of nodes and subtract 4 to account for nfs and self-heal
#numNodes=$(eval "$ssh \"
  #sed -n -e 's/.*<nodeCount>\([^<]*\)<\/nodeCount>.*/\1/p' $tmpfile\"")
#((numNodes-=4)) # account for nodes used for nfs and self-heal
#(( numNodes < 2 )) && {
  #echo "ERROR: cluster contains only $numNodes nodes, expect 2 or more";
  #exit 1; }

# extract the hostnames
#nodes="$(eval "$ssh \"
  #sed -n -e 's/.*<hostname>\([^<]*\)<\/hostname>/\1/p' $tmpfile | \
  #head -n $numNodes\"")"
# extract the bricks
#bricks=($(eval "$ssh \"
  #sed -n -e 's/.*<path>\([^<]*\)<\/path>/\1/p' $tmpfile | head -n $numNodes\""))

# output both
#i=0
#for node in $nodes; do
    #echo "$node:${bricks[$i]}"
    #((i++))
#done
