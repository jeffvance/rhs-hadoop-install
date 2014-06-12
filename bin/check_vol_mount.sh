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


# chk_mnt: given the passed-in existing vol mount opts and the passed-in
# expected mount options, verify the correct settings. Returns 1 for errors.
# Args:
#  1=node
#  2=current mount option values
#  3=expected mount option values
function chk_mnt() {

  local node="$1"; local curr_opts="$2"; local expt_opts="$3"
echo "**** curr_opts=$curr_opts, expt_opts=$expt_opts"
  # note "_" in option names below
  local historic_mnt_opts='entry_timeout=0.0000 attribute_timeout=0.0000'
  local errcnt=0; local warncnt=0; local mnt

  for mnt in $expt_opts; do
echo "*****error mnt=$mnt"
      if ! grep -q "$mnt" <<<$curr_opts; then
	echo "ERROR on $node: required gluster mount option $mnt must be set"
	((errcnt++))
      fi
  done

  for mnt in $historic_mnt_opts; do
echo "*****warn mnt=$mnt"
      if grep -q "$mnt" <<<$curr_opts; then
	echo "WARN on $node: \"${mnt//_/-}\" option should not be set"
	((warncnt++))
      fi
  done

  (( errcnt > 0  )) && return 1
  echo "$VOLNAME mount options are set correctly with $warncnt warnings"
  return 0
}

# check_vol_mnt_attrs: verify that the correct mount settings for VOLNAME have
# been set on the passed-in node. This include verifying both the "live" 
# settings, determined by gluster state, and the "persistent" settings,
# defined in /etc/fstab.
function check_vol_mnt_attrs() {

  local node="$1"
  local warncnt=0; local errcnt=0; local cnt; local mntopts; local pid;
  local state_file_dir='/var/run/gluster'
  local state_file='glusterdump.' # prefix
  local section='\[xlator.mount.fuse.priv\]'

  # live check:
  # find correct glusterfs pid
  pid=($(ssh $node "ps -ef | grep 'glusterfs --.*$VOLNAME' | grep -v grep"))
  pid=${pid[1]} # extract glusterfs pid, 2nd field
  # generate gluster state file
  ssh $node "kill -SIGUSR1 $pid"
  # copy state file back to local, expected to be 1 file but could match more
  state_file="$state_file${pid}.dump.[0-9]*" # glob -- don't know full name
  scp -q $node:/$state_file_dir/$state_file /tmp
  # assign exact state file name
  state_file=($(ls -r /tmp/$state_file)) # array in reverse order (new -> old)
  state_file="${state_file[0]}" # newest
  # extract mount opts section from state file
  mntopts="$(sed -n "/^$section/,/^$/p" $state_file)"
echo "*****LIVE chk_mnt $node '$mntopts' '${CHK_MNTOPTS//-/_}'"
  chk_mnt $node "$mntopts" "${CHK_MNTOPTS//-/_}" || ((errcnt++))

  # fstab check:
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
echo "***** fstab: chk_mnt $node '$mntopts' '$CHK_MNTOPTS'"
    chk_mnt $node "$mntopts" "$CHK_MNTOPTS" || ((errcnt++))
  fi

  (( errcnt > 0 )) && return 1
  echo "$VOLNAME mount setup correctly on $node with $warncnt warnings"
  return 0
}


## main ## 

errcnt=0; cnt=0
PREFIX="$(dirname $(readlink -f $0))"
CHK_MNTOPTS="$($PREFIX/gen_vol_mnt_options.sh)" # required mnt opts
CHK_MNTOPTS="${CHK_MNTOPTS//,/ }" # replace commas with spaces

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
