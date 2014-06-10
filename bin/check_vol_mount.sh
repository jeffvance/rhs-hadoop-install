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


# chk_mnt: given the passed-in vol mount opts, verify the correct settings.
# Returns 1 for errors.
function chk_mnt() {

  local node="$1"; local opts="$2"
  local errcnt=0; local warncnt=0; local mnt

  for mnt in $MNT_OPTS; do
      if ! grep -q "$mnt" <<<$opts; then
	echo "ERROR on $node: required gluster mount option $mnt must be set"
	((errcnt++))
      fi
  done

  (( errcnt > 0  )) && return 1
  return 0
}

# check_vol_mnt_attrs: verify that the correct mount settings for VOLNAME have
# been set on the passed-in node. This include verifying both the "live" 
# settings, determined by ps, and the "persistent" settings, defined in
# /etc/fstab.
function check_vol_mnt_attrs() {

  local node="$1"
  local warncnt=0; local errcnt=0; local cnt; local mntopts

  # live check
  mntopts="$(ssh $node "ps -ef | grep 'glusterfs --.*$VOLNAME' | grep -v grep")"
  mntopts=${mntopts#*glusterfs} # just the opts
  chk_mnt $node "$mntopts" || ((errcnt++))

  # fstab check
  cnt=$(ssh $node "grep -c '$VOLNAME\s.*\sglusterfs\s' /etc/fstab")
  if (( cnt == 0 )) ; then
    echo "ERROR on $node: $VOLNAME mount missing in /etc/fstab"
    ((errcnt++))
  elif (( cnt > 1 )) ; then
    echo "ERROR on $node: $VOLNAME appears more than once in /etc/fstab"
    ((errcnt++))
  else # cnt == 1
    mntopts="$(ssh $node "grep '$VOLNAME\s.*\sglusterfs\s' /etc/fstab")"
    mntopts=${mntopts#* glusterfs }
    chk_mnt $node "$mntopts" || ((errcnt++))
  fi

  (( errcnt > 0 )) && return 1
  echo "$VOLNAME mount setup correctly on $node with $warncnt warnings"
  return 0
}


## main ## 

errcnt=0; cnt=0
PREFIX="$(dirname $(readlink -f $0))"
MNT_OPTS="$($PREFIX/gen_vol_mnt_options.sh)" # required mnt opts
MNT_OPTS="${MNT_OPTS//,/ }" # replace commas with spaces

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
