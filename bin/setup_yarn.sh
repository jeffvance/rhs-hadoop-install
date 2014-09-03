#!/bin/bash
#
# setup_yarn.sh setup the supplied yarn-master node for the passed-in volume.
# So far, this includes creating the glusterfs-fuse mount.
# Syntax:
#   $1=volume name (required).
#   -y=yarn-master node (required).
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

PREFIX="$(dirname $(readlink -f $0))"
errcnt=0

# set_yarn: if the yarn node does not already have VOLNAME mounted then
# append the glusterfs-fuse volume mount to fstab and mount it. Note: since
# the yarn-master node is expected to be a RHEL server we may have to install
# glusterfs-fuse first.
# Uses globals:
#   PREFIX
#   RHS_NODE
#   VOLMNT
#   VOLNAME
#   YARN_NODE
function set_yarn() {

  local err; local ssh=''; local ssh_close=''
  local fuse_rpm='glusterfs-fuse'

  [[ "$YARN_NODE" != "$HOSTNAME" ]] && {
    ssh="ssh $YARN_NODE '"; ssh_close="'"; }

  eval "$ssh
	  # install glusterfs-fuse if not present
	  if ! rpm -ql $fuse_rpm >& /dev/null ; then
	    yum -y install $fuse_rpm 2>&1
	  fi
	  source $PREFIX/functions # for function call below
	  gluster_mnt_vol $RHS_NODE $VOLNAME $VOLMNT
	$ssh_close
       "
  err=$?
  (( err != 0 )) && {
    echo "ERROR $err on $YARN_NODE (yarn-master)";
    return 1; }

  echo "$VOLNAME glusterfs-fuse mounted on $YARN_NODE (yarn-master)"
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
[[ -z "$VOLMNT" ]] && {
  echo "ERROR: $VOLNAME not mounted (on $RHS_NODE)";
  exit 1; }

# set up a glusterfs-fuse mount for the volume if it's not already mounted
set_yarn || ((errcnt++))

(( errcnt > 0 )) && exit 1
echo "$VOLNAME is setup on $YARN_NODE (yarn-master)"
exit 0
