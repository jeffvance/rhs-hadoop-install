#!/bin/bash
#
# check_vol_mount.sh verifies that each node spanned by the supplied volume
# has the vol mount setup correctly. This include verifying both the "live"
# settings, determined by ps, and the "persistent" settings, defined in
# /etc/fstab.
# Syntax:
#   $1=volume name
#   $2=optional list of nodes to check
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.


# given the passed-in vol mount opts, verify the correct settings. Returns 1 
# for errors, 2 for warnings, and 0 for neither.
# Note: cannot return -1, just in case you were wondering...
function chk_mnt() {

  local node="$1"; local opts="$2"
  local errcnt=0; local warncnt=0; local mnt

  for mnt in $REQ_MNT_OPTS; do
      if ! grep -q "$mnt" <<<$opts; then
	echo "ERROR on $node: required gluster mount option $mnt must be set"
	((errcnt++))
      fi
  done

  for mnt in $OPT_MNT_OPTS; do
      if ! grep -q "$mnt" <<<$opts; then
	echo "WARN on $node: recommended gluster mount option $mnt can be set"
	((warncnt++))
      fi
  done

  (( errcnt > 0  )) && return 1 # 1 or more errors
  (( warncnt > 0 )) && return 2 # 1 or more warnings
  return 0
}

# check_vol_mnt_attrs: verify that the correct mount settings for VOLNAME have
# been set on the passed-in node. This include verifying both the "live" settings,
# determined by ps, and the "persistent" settings, defined in /etc/fstab.
function check_vol_mnt_attrs() {

  local node="$1"
  local rc; local errcnt=0; local warncnt=0; local cnt; local mntopts

  # live check
  mntopts="$(ssh $node "ps -ef | grep 'glusterfs --.*$VOLNAME' | grep -v grep")"
  mntopts=${mntopts#*glusterfs} # just the opts
  chk_mnt $node "$mntopts"
  rc=$?
  (( rc == 1 )) && ((errcnt++)) || (( rc == 2 )) && ((warncnt++))

  # fstab check
  cnt=$(ssh $node "grep -c '$node:/$VOLNAME.* glusterfs ' /etc/fstab")
  if (( cnt == 0 )) ; then
    echo "ERROR: $VOLNAME mount missing in /etc/fstab"
    ((errcnt++))
  elif (( cnt > 1 )) ; then
    echo "ERROR: $VOLNAME appears more than once in /etc/fstab"
    ((errcnt++))
  else # cnt == 1
    mntopts="$(ssh $node "grep '$node:/$VOLNAME.* glusterfs ' /etc/fstab")"
    mntopts=${mntopts#* glusterfs }
    chk_mnt $node "$mntopts"
    rc=$?
    (( rc == 1 )) && ((errcnt++)) || (( rc == 2 )) && ((warncnt++))
  fi

  (( errcnt > 0 )) && return 1
  echo "$VOLNAME mount setup correctly on $node with $warncnt warnings"
  return 0
}


## main ## 

errcnt=0; cnt=0
PREFIX="$(dirname $(readlink -f $0))"
REQ_MNT_OPTS="$($PREFIX/gen_req_gluster_mnt.sh)" # required mnt opts
OPT_MNT_OPTS="$($PREFIX/gen_opt_gluster_mnt.sh)" # optional mnt opts
REQ_MNT_OPTS="${REQ_MNT_OPTS//,/ }" # subst spaces for commas
OPT_MNT_OPTS="${OPT_MNT_OPTS//,/ }" # subst spaces for commas

# parse cmd opts
while getopts ':n:' opt; do
    case "$opt" in
      n)
        rhs_node="$OPTARG"
        ;;
      \?) # invalid option
	;;
    esac
done
shift $((OPTIND-1))

VOLNAME="$1"; shift
[[ -z "$VOLNAME" ]] && {
  echo "Syntax error: volume name is required";
  exit -1; }

[[ -n "$rhs_node" ]] && rhs_node="-n $rhs_node" || rhs_node=''

NODES="$@" # optional list of nodes
[[ -z "$NODES" ]] && NODES="$($PREFIX/find_nodes.sh $rhs_node $VOLNAME)" 

for node in $NODES; do
    ((cnt++)) # num of nodes
    check_vol_mnt_attrs $node || ((errcnt++))
done

(( errcnt > 0 )) && exit 1
echo "The $cnt nodes spanned by $VOLNAME have the correct vol mount settings"
exit 0
