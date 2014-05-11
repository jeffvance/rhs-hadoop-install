#!/bin/bash
#
# find_volmnt.sh discovers the gluster volume mount directory for the passed in
# volume (required). A single line containing just the vol-mnt" is output.
#
# Assumption: the node running this script has access to the gluster cli.

VOLNAME="$1"
[[ -z "$VOLNAME" ]] && {
  echo "Syntax error: volume name is required";
  exit -1;}

LOCALHOST=$(hostname)
PREFIX="$(dirname $(readlink -f $0))"

BRICKS=($($PREFIX/find_bricks.sh $VOLNAME)) # array
node=${BRICKS[0]%:*}
[[ "$node" == "$LOCALHOST" ]] && { ssh=''; ssh_close=''; } || \
				 { ssh="ssh $node '"; ssh_close="'"; }

eval "$ssh 
	mnt=(\$(grep -w $VOLNAME /proc/mounts)) # array
	echo \${mnt[1]} # node:/volmnt
      $ssh_close
"
