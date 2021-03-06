#!/bin/bash
#
# setup_yarn.sh setup this node (localhost), expected to be the yarn-master
# node, using the passed-in volume name and volume mount. So far this includes
# creating the glusterfs-fuse mount.
# Note: volume mount was added so that passwordless ssh from localhost (yarn-
#   node) to the -n node (rhs-node) is not required.
# Syntax:
#   $1=volume name (required).
#   $2=volume mount which includes the volname (required).
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

PREFIX="$(dirname $(readlink -f $0))"
errcnt=0

source $PREFIX/functions # for function calls below


# yarn_mount: if the yarn node does not already have VOLNAME mounted then
# append the glusterfs-fuse volume mount to fstab and mount it. Note: since
# the yarn-master node is expected to be a RHEL server we may have to install
# glusterfs-fuse first.
# Uses globals:
#   PREFIX
#   RHS_NODE
#   VOLMNT
#   VOLNAME
function yarn_mount() {

  local err; local fuse_rpm='glusterfs-fuse'

  # install glusterfs-fuse if not present
  if ! rpm -ql $fuse_rpm >& /dev/null ; then
    yum -y install $fuse_rpm 2>&1
  fi

  gluster_mnt_vol $RHS_NODE $VOLNAME $VOLMNT
  err=$?

  (( err != 0 )) && {
    echo "ERROR $err on $HOSTNAME (yarn-master)";
    return 1; }

  echo "$VOLNAME glusterfs-fuse mounted on $HOSTNAME (yarn-master)"
  return 0
}


## main ##

# parse cmd opts
while getopts ':n:' opt; do
    case "$opt" in
      n)
        RHS_NODE="$OPTARG"
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

VOLMNT="$2"
[[ -z "$VOLMNT" ]] && {
  echo "Syntax error: volume mount is required";
  exit -1; }

[[ -z "RHS_NODE" ]] && RHS_NODE="$HOSTNAME"

# set up a glusterfs-fuse mount for the volume if it's not already mounted
yarn_mount || ((errcnt++))

(( errcnt > 0 )) && exit 1
echo "$VOLNAME is setup on $HOSTNAME (yarn-master)"
exit 0
