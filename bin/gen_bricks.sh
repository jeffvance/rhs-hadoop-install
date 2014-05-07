#!/bin/bash
#
# gen_bricks.sh outputs a list of brick names (node:/brick-path), one brick per
# line, for the supplied volume, brick mount, and list of nodes.
# Args: 1=volume name, 2=brick mount dir, 3=list of nodes
#
# Assumption: all nodes have the same brick mount.
#
VOLNAME="$1"
BRICK_MNT="$2"
shift 2
NODES="$@"

for node in $NODES; do
    echo "$node:/$BRICK_MNT/$VOLNAME"
done
