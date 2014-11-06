#!/bin/bash
#
# setup_yarn.sh setup this node (localhost), expected to be the yarn-master
# node, using the passed-in volume name. So far this includes creating the
# glusterfs-fuse mount, and creating the local <brickmnt>/hadoop/yarn/timeline
# directory.
# Syntax:
#   $1=volume name (required).
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

PREFIX="$(dirname $(readlink -f $0))"
errcnt=0

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

  source $PREFIX/functions # for function call below
  gluster_mnt_vol $RHS_NODE $VOLNAME $VOLMNT
  err=$?

  (( err != 0 )) && {
    echo "ERROR $err on $HOSTNAME (yarn-master)";
    return 1; }

  echo "$VOLNAME glusterfs-fuse mounted on $HOSTNAME (yarn-master)"
  return 0
}

# yarn_mkdirs: create the local directories needed on the yarn node. Returns 1
# on errors. POSIX group is assumed to be 'hadoop'.
# Uses globals:
#   BRKMNTXXXXXXXXXXX
#   PREFIX
function yarn_mkdirs() {

  # fmt: <dir>:<perms>:<owner>
  local dirs='hadoop/yarn:0755:yarn hadoop/yarn/timeline:0755:yarn'
  local err

  $PREFIX/add_dirs.sh $BRKMNTXXXXXXX $dirs # local dirs on localhost
  err=$?
  (( err != 0 )) && {
    echo "ERROR $err: adding local yarn-specific dirs";
    return 1; }

  echo "added \"$dirs\" local directories to $HOSTNAME (yarn-master)"
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

[[ -n "$RHS_NODE" ]] && RHS_NODE_OPT="-n $RHS_NODE" || RHS_NODE_OPT=''

# get volume mount
VOLMNT="$($PREFIX/find_volmnt.sh $RHS_NODE_OPT $VOLNAME)" # includes volname
[[ -z "$VOLMNT" ]] && {
  echo "ERROR: $VOLNAME not mounted (on $RHS_NODE)";
  exit 1; }

# get brick mount
BRKMNTS="$($PREFIX/find_brick_mnts.sh -x $RHS_NODE_OPT)"
[[ -z "$BRKMNTS" ]] && {
  echo "ERROR: $VOLNAME not mounted (on $RHS_NODE)";
  exit 1; }
# set up a glusterfs-fuse mount for the volume if it's not already mounted
yarn_mount || ((errcnt++))

# create local dirs residing only on the yarn node
yarn_mkdirs || ((errcnt++))

(( errcnt > 0 )) && exit 1
echo "$VOLNAME is setup on $HOSTNAME (yarn-master)"
exit 0
