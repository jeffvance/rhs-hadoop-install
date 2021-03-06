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
# 8) stop the ambari-agent on all storage nodes +
# 9) stop, reset and setup the ambari-server +
# ** gluster cmd only done once for entire pool; all other cmds executed on
#    each node
# +  only if --reset-ambari is specified
#
# Args:
#   --rhs-node <node>, storage node to run gluster cli commands on
#   --yarn-master <node>, yarn-master node
#   [--hadoop-mgmt-node <node>], ambari mgmt node
#   [--reset-ambari], flag to stop and reset ambari-server and agents
#
# WARNING!! EXISTING DATA WILL BE DELETED!
#

no_yes=('no' 'yes')

PREFIX="$(dirname $(readlink -f $0))"

source $PREFIX/functions


# parse cmd opts
reset_ambari=0 # false
mgmt_node=''
opts='rhs-node:,yarn-master:,hadoop-mgmt-node:,reset-ambari'

eval set -- "$(getopt -o '' --long $opts -- $@)"

while true; do
    case "$1" in
	--rhs-node)
          rhs_node="$2"; shift 2; continue
	;;
	--yarn-master)
          yarn_node="$2"; shift 2; continue
	;;
	--hadoop-mgmt-node)
          mgmt_node="$2"; shift 2; continue
	;;
	--reset-ambari)
          reset_ambari=1; shift; continue
	;;
	--)
	  shift; break
	;;
    esac
done

# sematic checking
[[ -n "$1" ]] && {
  echo "Syntax error: unexpected command arguments";
  exit -1; }

[[ -z "$rhs_node" ]] && {
  echo "Syntax error: --rhs-node is required";
  exit -1; }

[[ -z "$yarn_node" ]] && {
  echo "Syntax error: --yarn-master is required";
  exit -1; }

(( reset_ambari )) && [[ -z "$mgmt_node" ]] && {
  echo "Syntax error: mgmt node is required in order to reset ambari";
  exit -1; }

force "**********"
force "** USE AT YOUR OWN RISK! THIS SCRIPT IS NOT SAFE!"
force "** This script will delete all of the data in the storage pool! It also"
force "** removes the bricks and volume mounts per node, detaches the storage"
force "** pool, and restarts glusterd on each node."
force "**********"
yesno "  Are you sure you want to continue? [y|N] " || exit 1


# check for passwordless ssh to the supplied rhs node
check_ssh $rhs_node || exit 1

# find bricks, nodes, and volumes in pool
VOLS="$($PREFIX/find_volumes.sh -n $rhs_node)"  # all volumes in pool
(( $? != 0 )) || [[ -z "$VOLS" ]]  &&
  warn "cannot find volume(s). $VOLS"

NODES="$($PREFIX/find_nodes.sh -un $rhs_node)"  # all storage nodes in pool
(( $? != 0 )) && {
  err "cannot find trusted pool nodes. $NODES";
  exit 1; }

BRICKS="$($PREFIX/find_brick_mnts.sh -xn $rhs_node)" # all bricks in pool
(( $? != 0 )) || [[ -z "$BRICKS" ]]  &&
  warn "cannot find brick mounts. $BRICKS"

# find all volume mounts in pool
VOLMNTS=''
for vol in $VOLS; do
    mnt="$($PREFIX/find_volmnt.sh -n $rhs_node $vol) "
    (( $? != 0 )) || [[ -z "$mnt" ]]  && {
	err "cannot find $vol volume mount on $rhs_node. $mnt";
	err "$vol may not be mounted. Either mount volume on $rhs_node or supply a different storage node."
	exit 1; }
    VOLMNTS+="$mnt "
done

# reduce to unique bricks
BRICKS=($(printf '%s\n' "$BRICKS" | sort -u))

# check for passwordless ssh to the storage and yarn nodes
check_ssh $(uniq_nodes $NODES $yarn_node $mgmt_node) || exit 1

echo
force "** The following nodes, volumes, bricks and vol mounts are affected:"
force "     nodes       : $(echo $NODES   | sed 's/ /, /g')"
force "     volumes     : $(echo $VOLS    | sed 's/ /, /g')"
force "     bricks      : $(echo $BRICKS  | sed 's/ /, /g')"
force "     vol mnts    : $(echo $VOLMNTS | sed 's/ /, /g')"
force "     yarn-node   : $yarn_node"
[[ -n "$mgmt_node" ]] &&
  force "     mgmt-node   : $mgmt_node"
force "     reset ambari: ${no_yes[$reset_ambari]}"
echo

yesno "  Continue? [y|N] " || exit 1

echo
force "-- restart glusterd on all nodes..."
for node in $NODES; do
    ssh $node "killall -r gluster && sleep 2 && \
	rm -rf /var/lib/glusterd/* && \
	service glusterd start"
done

echo
force "-- stop and delete the volumes..."
for vol in $VOLS; do
    ssh $rhs_node "gluster --mode=script volume stop $vol && sleep 1 && \
	gluster --mode=script volume delete $vol"
done

echo
force "-- detach all nodes from the pool..."
for node in $NODES; do
    [[ "$node" == "$rhs_node" ]] && continue # skip node executing peer detach
    ssh $rhs_node "gluster peer detach $node force"
done

echo
force "-- unmount and remove all vols and bricks mounts..."
for node in $(uniq_nodes $NODES $yarn_node); do
    ssh $node "
	for mnt in $VOLMNTS $BRICKS; do
	    if $PREFIX/find_mount.sh --live --vol --rtn-exists --filter \$mnt \
	    || $PREFIX/find_mount.sh --live --brick --rtn-exists \
		--filter \$mnt ; then
	      umount \$mnt
	    fi
	    if $PREFIX/find_mount.sh --fstab --vol --rtn-exists --filter \$mnt \
	    || $PREFIX/find_mount.sh --fstab --brick --rtn-exists \
		--filter \$mnt ; then
	      sed -i '\|$mnt|d' /etc/fstab
	    fi
	    [[ -e \$mnt ]] && rm -rf \$mnt
	done
	"
done

if (( reset_ambari )) ; then
  echo
  force "-- reset ambari agents and server..."
  for node in $(uniq_nodes $NODES $yarn_node); do
      ssh -tq -o 'BatchMode yes' $node "ambari-agent stop"
  done
  ssh -tq -o 'BatchMode yes' $mgmt_node "ambari-server stop; \
	ambari-server reset -s; \
	ambari-server setup -s"
fi

echo
force "** cleanup complete"
exit
