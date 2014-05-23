#!/bin/bash
#
# setup_yarn.sh setup the supplied yarn-master node for the passed-in volume. So
# far, this includes assigning the nfs mount.
# Syntax:
#   $1=volume name (required).
#   -y=yarn-master node (required).
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

PREFIX="$(dirname $(readlink -f $0))"
errcnt=0

# inside_pool: return 0 if the passed-in node is inside the storage pool, else
# return 1.
# Uses globals:
#   PREFIX
#   RHS_NODE_OPT
#   VOLNAME
function inside_pool() {

  local test_node="$1" # is this node inside the pool?
  local node

  for node in $($PREFIX/find_nodes.sh -u $RHS_NODE_OPT $VOLNAME); do
    [[ "$node" == "$test_node" ]] && return 0 # test node is inside pool
  done
  return 1 # test node is not inside pool
}

# set_yarn: if the yarn node does not already have VOLNAME nfs-mounted then
# append the nfs volume mount to fstab and mount it. 
# Assumption: the yarn-node is outside of the storage pool.
# Uses globals:
#   RHS_NODE
#   VOLMNT
#   VOLNAME
#   YARN_NODE
function set_yarn() {

  local err; local out; local ssh=''; local ssh_close=''
  local volmnt="$VOLMNT" # same name as gluster-fuse mnt
  local mntopts='defaults,_netdev'

  [[ "$YARN_NODE" != "$HOSTNAME" ]] && { ssh="ssh $YARN_NODE '"; ssh_close="'"; }

  out="$(eval "
  	$ssh
	  # append to fstab if not present
	  if ! grep -qs \"$RHS_NODE:/$VOLNAME.* nfs \" /etc/fstab ; then
	    echo $RHS_NODE:/$VOLNAME $volmnt nfs $mntopts 0 0 >>/etc/fstab
	  fi
	  # always attempt to create the dir and mount the vol, ok if not needed
	  mkdir -p $volmnt
	  mount $volmnt 2>&1 # mount via fstab, exit with mount returncode
	$ssh_close
      ")"
  err=$?
  (( err != 0 && err != 32 )) && { # 32==already mounted
    echo "ERROR $err on $YARN_NODE (yarn-master): $out";
    return 1; }

  echo "$VOLNAME nfs mounted on $YARN_NODE (yarn-master)"
  return 0
}


# parse cmd opts
while getopts ':n:y:' opt; do
    case "$opt" in
      n)
        RHS_NODE="$OPTARG"
        ;;
      y)
        YARN_NODE="$OPTARG"
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

[[ -z "$YARN_NODE" ]] && {
  echo "Syntax error: yarn-master node is required";
  exit -1; }

[[ -n "$RHS_NODE" ]] && RHS_NODE_OPT="-n $RHS_NODE" || RHS_NODE_OPT=''

# get volume mount
VOLMNT="$($PREFIX/find_volmnt.sh $RHS_NODE_OPT $VOLNAME)" # includes volname

# set up the volume nfs mount if the yarn node is outside of the pool. Note: if
# the yarn node is inside the pool then the gluster-fuse mount will suffice.
if ! inside_pool $YARN_NODE ; then
  set_yarn || ((errcnt++))
fi

(( errcnt > 0 )) && exit 1
echo "$VOLNAME is setup on $YARN_NODE (yarn-master)"
exit 0
