#!/bin/bash
#
# check_vol_mount.sh verifies that each node spanned by the supplied volume
# has the vol mount setup correctly. This include verifying both the "live"
# settings, determined by ps, and the "persistent" settings, defined in
# /etc/fstab.
# Syntax:
#  $1=volume name
#  $2=optional list of nodes to check
#  -q, if specified, means only set the exit code, do not output anything
#
# Assumption: the node running this script has access to the gluster cli.

errcnt=0

prefix="$(dirname $(readlink -f $0))"
[[ ${prefix##*/} != 'bin' ]] && prefix+='/bin'

# parse cmd opts
while getopts ':q' opt; do
    case "$opt" in
      q)
	quiet=true  # else, undefined
        shift
	;;
      \?) # invalid option
	shift # silently ignore opt
	;;
    esac
done

VOLNAME="$1"
NODES="$2" # optional
[[ -z "$NODES" ]] && NODES="$($prefix/find_nodes.sh $VOLNAME)" 

# copy companion volmnt check script to target node and execute it
for node in $NODES; do
    scp -q $prefix/check_vol_mnt_attrs.sh $node:/tmp
    out="$(ssh $node /tmp/check_vol_mnt_attrs.sh $VOLNAME)"
    if (( $? != 0 )) ; then
      [[ -z "$quiet" ]] && echo "$node: $out"
      ((errcnt++))
    fi
done

(( errcnt > 0 )) && exit 1
[[ -z "$quiet" ]] && echo \
	"All nodes spanned by $VOLNAME have the correct volume mount settings"
exit 0
