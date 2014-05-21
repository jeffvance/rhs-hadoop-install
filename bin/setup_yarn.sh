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

# set_yarn: if the yarn node does not already have VOLNAME nfs-mounted then
# append the nfs volume mount to fstab and mount it.
function set_yarn() {

  local out; local ssh=''; local ssh_close=''; local err
  local volmnt="${VOLMNT}_nfs"
  local mntopts='defaults,_netdev'

  [[ "$yarn_node" != "$HOSTNAME" ]] && { ssh="ssh $yarn_node '"; ssh_close="'"; }

  out="$(eval "
  	$ssh
	  # append to fstab if not present
	  if ! grep -qs \"$yarn_node:/$VOLNAME.* nfs \" /etc/fstab ; then
	    echo $yarn_node:/$VOLNAME $volmnt nfs $mntopts 0 0 >>/etc/fstab
	    mkdir -p $volmnt
	    mount $volmnt 2>&1 # mount via fstab, exit with mount returncode
	  fi
	$ssh_close
      ")"
  err=$?
  (( err != 0 && err != 32 )) && { # 32==already mounted
    echo "ERROR $err on $yarn_node (yarn-master): $out";
    return 1; }

  echo "$VOLNAME nfs mounted on $yarn_node"
  return 0
}


# parse cmd opts
while getopts ':n:y:' opt; do
    case "$opt" in
      n)
        rhs_node="$OPTARG"
        ;;
      y)
        yarn_node="$OPTARG"
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

[[ -z "$yarn_node" ]] && {
  echo "Syntax error: yarn-master node is required";
  exit -1; }

[[ -n "$rhs_node" ]] && rhs_node="-n $rhs_node" || rhs_node=''

# get volume mount
VOLMNT="$($PREFIX/find_volmnt.sh $rhs_node $VOLNAME)"

# set up the volume nfs mount
set_yarn || ((errcnt++))

(( errcnt > 0 )) && exit 1
echo "$VOLNAME is setup on $yarn_node (yarn-master)"
exit 0
