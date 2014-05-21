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

# set_yarn: define the nfs mount for VOLNAME on the yarn-master node.
function set_yarn() {

  local out; local ssh; local ssh_close
  local volmnt="${VOLMNT}_nfs"
  local mntopts='defaults,_netdev'

  [[ "$yarn_node" == "$HOSTNAME" ]] && { ssh='('; ssh_close=')'; } \
				    || { ssh="ssh $yarn_node '"; ssh_close="'"; }
  out="$(eval "
  	$ssh
	  mkdir -p $volmnt
	  # append to fstab if not present
	  if ! grep -qsw $volmnt /etc/fstab ; then
	    echo $yarn_node:/$VOLNAME $volmnt nfs $mntopts 0 0 >>/etc/fstab
	  fi
	  mount $volmnt # mount via fstab
	  rc=\$?
	  if (( rc != 0 && rc != 32 )) ; then # 32=already mounted
            echo Error \$rc: mounting $volmnt with $mntopts options
            exit 1 # from ssh or sub-shell
	  fi
	  exit 0 # from ssh or sub-shell
	$ssh_close
      ")"
  (( $? != 0 )) && {
    echo "ERROR on $yarn_node: $out";
    return 1; }

  echo "$VOLNAME nfs mount setup on $node"
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
echo "$VOLNAME is setup on yarn-master $yarn_node"
exit 0
