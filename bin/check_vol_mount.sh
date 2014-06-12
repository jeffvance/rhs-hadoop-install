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
# expected mount options, verify the correct settings. Returns 1 for errors
# and returns 2 for warnings.
# Args:
#  1=current mount options
#  2=expected required mount options (live or fstab)
#  3=expected mount options to warn against (live or fstab)
function chk_mnt() {

  local curr_opts="$1"; local expt_opts="$2"; local warn_opts="$3"
  local errcnt=0; local warncnt=0; local mnt

  for mnt in $expt_opts; do
      if ! grep -q "$mnt" <<<$curr_opts; then
	echo "ERROR: required gluster mount option $mnt must be set"
	((errcnt++))
      fi
  done

  for mnt in $warn_opts; do
      if grep -q "$mnt" <<<$curr_opts; then
	echo "WARN: \"$mnt\" option should not be set"
	((warncnt++))
      fi
  done

  (( errcnt > 0  )) && return 1
  (( warncnt > 0 )) && return 2
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
  local err

  # live check:
  echo "--- $node: live $VOLNAME mount options check..."
  live_check "$CHK_MNTOPTS_LIVE" "$CHK_MNTOPTS_LIVE_WARN"
...
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
  mntopts="$(sed -n "/^$section/,/^$/p" $state_file | tr '\n' ' ')"
  # verify the current mnt options
  chk_mnt "$mntopts" "$CHK_MNTOPTS_LIVE" "$CHK_MNTOPTS_LIVE_WARN"
  err=$?
  if (( err == 1 )) ; then
    ((errcnt++))
  elif (( err = 2 )) ; then
    ((warncnt++))
  fi

  # fstab check:
  echo "--- $node: /etc/fstab $VOLNAME mount options check..."
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
    chk_mnt "$mntopts" "$CHK_MNTOPTS" "$CHK_MNTOPTS_WARN"
    err=$?
    if (( err == 1 )) ; then
      ((errcnt++))
    elif (( err = 2 )) ; then
      ((warncnt++))
    fi
  fi

  (( errcnt > 0 )) && return 1

  echo -n "$VOLNAME mount setup correctly on $node"
  (( warncnt > 0 )) && echo -n " with warnings"
  echo # flush
  return 0
}


## main ## 

errcnt=0; cnt=0
PREFIX="$(dirname $(readlink -f $0))"

# assign all combos of mount options (live, fstab, warn, required)
CHK_MNTOPTS="$($PREFIX/gen_vol_mnt_options.sh)" # required fstab mnt opts
CHK_MNTOPTS="${CHK_MNTOPTS//,/ }" # replace commas with spaces
CHK_MNTOPTS_LIVE="$($PREFIX/gen_vol_mnt_options.sh -l)" # live required mnt opts
CHK_MNTOPTS_LIVE="${CHK_MNTOPTS_LIVE//,/ }"
CHK_MNTOPTS_WARN="$($PREFIX/gen_vol_mnt_options.sh -w)" # fstab opts to warn on
CHK_MNTOPTS_WARN="${CHK_MNTOPTS_WARN//,/ }"
CHK_MNTOPTS_LIVE_WARN="$($PREFIX/gen_vol_mnt_options.sh -wl)" # live-warn opts
CHK_MNTOPTS_LIVE_WARN="${CHK_MNTOPTS_LIVE_WARN//,/ }"

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
