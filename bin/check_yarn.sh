#!/bin/bash
#
# check_yarn.sh verifies that the yarn-master node is setup correctly. So far,
# this includes checking the nfs mount.
# Syntax:
#   $1=volume name (required).
#   -y=(optional) yarn-master node, default=localhost.

errcnt=0

# chk_yarn: verify that the volume has been established mounted on the yarn-
# master node. This includes verifying both the "live" settings, determined
# by ps, and the "persistent" settings, defined in /etc/fstab. The volume can
# be nfs mounted, CIFS mounted, gluster-fuse mounted, etc -- doesn't matter.
function chk_yarn() {

  local errcnt=0; local warncnt=0; local cnt

  # live check
  if ! eval "$SSH ps -ef | \
	grep \"glusterfs --.*$VOLNAME\" | \
	grep -vq grep $SSH_CLOSE" ; then
    echo "ERROR: $VOLNAME not mounted on $YARN_NODE (yarn-master)"
    ((errcnt++))
  fi

  # fstab check
  cnt=$(eval "$SSH
	grep -c \"$VOLNAME\s.*\sglusterfs\s\" /etc/fstab $SSH_CLOSE")
  if (( cnt == 0 )) ; then
    echo "WARN: $VOLNAME mount missing from /etc/fstab on $YARN_NODE (yarn-master)"
    ((warncnt++))
  elif (( cnt > 1 )) ; then
    echo "WARN: $VOLNAME mount appears more than once in /etc/fstab on $YARN_NODE (yarn-master)"
    ((warncnt++))
  fi

  (( errcnt > 0 )) && return 1
  echo "$VOLNAME mount setup correctly on $YARN_NODE (yarn-master) with $warncnt warnings"
  return 0
}


# parse cmd opts
while getopts ':y:' opt; do
    case "$opt" in
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

[[ -z "$YARN_NODE" ]] && YARN_NODE="$HOSTNAME"

[[ "$YARN_NODE" == "$HOSTNAME" ]] && { SSH=''; SSH_CLOSE=''; } \
				  || { SSH="ssh $YARN_NODE '"; SSH_CLOSE="'"; }

chk_yarn || ((errcnt++))

(( errcnt > 0 )) && exit 1
exit 0
