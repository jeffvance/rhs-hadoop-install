#!/bin/bash
#
# check_yarn.sh verifies that the yarn-master node is setup correctly. So far,
# this includes checking the nfs mount.
# Syntax:
#   $1=volume name (required).
#   -y=yarn-master node (required).

LOCALHOST=$(hostname)
errcnt=0

# chk_yarn: verify that the nfs mount for VOLNAME has been established on the
# yarn-master node. This include verifying both the "live" settings, determined
# by ps, and the "persistent" settings, defined in /etc/fstab.
function chk_yarn() {

  local errcnt=0; local warncnt=0; local cnt

  # live check
  if ! eval "$SSH ps -ef | grep -q '$yarn_node:/$VOLNAME.* nfs '" ; then
    ((errcnt++))
  fi

  # fstab check
  cnt=$(eval "$SSH \"grep -c '$yarn_node:/$VOLNAME.* nfs ' /etc/fstab\"")
  if (( cnt == 0 )) ; then
    echo "ERROR: $VOLNAME nfs mount missing in /etc/fstab on $yarn_node (yarn-master)"
    ((errcnt++))
  elif (( cnt > 1 )) ; then
    echo "WARN: $VOLNAME nfs mount appears more than once in /etc/fstab on $yarn_node (yarn-master)"
    ((warncnt++))
  fi

  (( errcnt > 0 )) && return 1
  echo "$VOLNAME mount setup correctly on $yarn_node (yarn-master) with $warncnt warnings"
  return 0
}


# parse cmd opts
while getopts ':y:' opt; do
    case "$opt" in
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

[[ "$yarn_node" == "$LOCALHOST" ]] && SSH='' || SSH="ssh $yarn_node"

chk_yarn || ((errcnt++))

(( errcnt > 0 )) && exit 1
echo "$VOLNAME is setup correctly on yarn-master $yarn_node"
exit 0
