#!/bin/bash
#
# .cleanup.sh is a hidden script to undo all (or most) of the work done by
# setup_cluster.sh, create_vol.sh, and enable_vol.sh. This script is to be
# used at the user's own risk.
#
# Steps performed by this script:
# 1) re-start glusterd
# 2) stop vol **
# 3) delete vol **
# 4) detach nodes
# 5) umount vol if mounted
# 6) unmount brick_mnt if mounted
# 7) remove the brick and gluster mount records from /etc/fstab
# ** gluster cmd only done once for entire pool; all other cmds executed on
#    each node
#
# Args:
#   -n rhs-node to run gluster cli commands on
#   -y yarn-master node
#
# WARNING!! EXISTING DATA WILL BE DELETED!
#

PREFIX="$(dirname $(readlink -f $0))"

source $PREFIX/functions

# parse cmd opts
while getopts ':n:y:' opt; do
    case "$opt" in
      n) # rhs-node
        rhs_node="$OPTARG"
        ;;
      y) # yarn node
        yarn_node="$OPTARG"
        ;;
      \?) # invalid option
        ;;
    esac
done
shift $((OPTIND-1))

[[ -n "$1" ]] && {
  echo "Syntax error: no arguments allowed other than -n and -y"
  exit -1; }

[[ -z "$rhs_node" ]] && {
  echo "Syntax error: -n arg is required";
  exit -1; }

[[ -z "$yarn_node" ]] && {
  echo "Syntax error: -y arg is required";
  exit -1; }

echo "**********"
echo "** USE AT YOUR OWN RISK! THIS SCRIPT IS NOT SAFE!"
echo "** This script will delete all of the data in the storage pool! It also"
echo "** removes the bricks and volume mounts per node, detaches the storage"
echo "** pool, and restarts glusterd on each node."
echo "**********"
yesno "  Are you sure you want to continue? [y|N] " || exit 1


# find bricks, nodes, and volumes in pool
VOLS="$($PREFIX/find_volumes.sh -n $rhs_node)"  # all volumes in pool
NODES="$($PREFIX/find_nodes.sh -un $rhs_node)"  # all storage nodes in pool
BRICKS="$($PREFIX/find_brick_mnts.sh -xn $rhs_node)" # all bricks in pool

# find all volume mounts in pool
VOLMNTS=''
for vol in $VOLS; do
    VOLMNTS+="$($PREFIX/find_volmnt.sh -n $rhs_node $vol) "
done

# reduce to unique bricks
BRICKS=($(printf '%s\n' "$BRICKS" | sort -u))

# check for passwordless ssh to the supplied storage nodes
check_ssh $NODES $yarn_node || exit 1

echo
echo "** The following nodes, volumes, bricks and vol mounts are affected:"
echo "     nodes     : $(echo $NODES   | sed 's/ /, /g')"
echo "     volumes   : $(echo $VOLS    | sed 's/ /, /g')"
echo "     bricks    : $(echo $BRICKS  | sed 's/ /, /g')"
echo "     vol mnts  : $(echo $VOLMNTS | sed 's/ /, /g')"
echo "     yarn-node : $yarn_node"
echo
yesno "  Continue? [y|N] " || exit 1

echo
echo "-- restart glusterd on all nodes..."
for node in $NODES; do
    ssh $node "killall -r gluster && sleep 2 && \
	rm -rf /var/lib/glusterd/* && \
	service glusterd start"
done

echo
echo "-- stop and delete the volumes..."
for vol in $VOLS; do
    ssh $rhs_node "gluster --mode=script volume stop $vol && sleep 1 && \
	gluster --mode=script volume delete $vol"
done

echo
echo "-- detach all nodes from the pool..."
for node in $NODES; do
    [[ "$node" == "$rhs_node" ]] && continue # skip node executing peer detach
    ssh $rhs_node "gluster peer detach $node force"
done

echo
echo "-- unmount and remove all vols and bricks mounts..."
for node in $NODES $yarn_node; do
    ssh $node "
	for mnt in $VOLMNTS $BRICKS; do
	    if grep -qs \$mnt /proc/mounts ; then
	      umount \$mnt
	    fi
	    if grep -wqs \$mnt /etc/fstab ; then # delete from fstab
	      sed -i '\|\$mnt|d' /etc/fstab
	    fi
	    [[ -e \$mnt ]] && rm -rf \$mnt
	done
	"
done

echo "** cleanup complete"
exit
