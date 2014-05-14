#!/bin/bash
#
# find_bricks.sh discovers the bricks for the trusted storage pool, or for the
# given volume if the <volName> arg is supplied. In either case, the list of
# bricks, "<node>:/<brick-mnt-dir>", are output, one brick per line.
#
# Assumption: the node running this script has access to the gluster cli.

VOLNAME="$1" # optional volume name

if gluster volume status $VOLNAME >& /dev/null ; then
  gluster volume status $VOLNAME | grep -w "Brick" | awk '{print $2}'
else
  exit 1
fi

exit 0
