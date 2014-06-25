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
# settings, defined by gluster state; and the "persistent" settings, defined
# in /etc/fstab.
function check_vol_mnt_attrs() {

  local node="$1"
  local warncnt=0; local errcnt=0; local err

  # live_check: secondary function to check the mount options seen in the
  # gluster "state" file. This file is produced when sending the glusterfs
  # client pid the SIGUSR1 signal. Returns 1 on errors, or the chk_mnt()
  # rtn-code.
  function live_check() {

    local node="$1"
    local mntopts; local pid
    local state_file_dir='/var/run/gluster'
    local state_file='glusterdump.' # prefix
    local section='^\[xlator.mount.fuse.priv\]'

    # find correct glusterfs pid
    pid=($(ssh $node "ps -ef | grep 'glusterfs --.*$VOLNAME' | grep -v grep"))
    pid=${pid[1]} # extract glusterfs pid, 2nd field
    [[ -z "$pid" ]] && {
      echo "ERROR: glusterfs client process not running";
      return 1; }

    # generate gluster state file
    ssh $node "kill -SIGUSR1 $pid"

    # copy state file back to local, expected to be 1 file but could match more
    state_file="$state_file${pid}.dump.[0-9]*" # glob -- don't know full name
    scp $node:/$state_file_dir/$state_file /tmp

    # assign exact state file name
    state_file=($(ls -r /tmp/$state_file)) # array in reverse order (new -> old)
    state_file="${state_file[0]}" # newest

    # extract mount opts section from state file
    mntopts="$(sed -n "/^$section/,/^\[/p" $state_file | tr '\n' ' ')"

    # verify the current mnt options and return chk_mnts rtncode
    chk_mnt "$mntopts" "$CHK_MNTOPTS_LIVE" "$CHK_MNTOPTS_LIVE_WARN"
  }

  # fstab: secondary function to check the mount options in /etc/fstab.
  # Returns 1 on errors and 2 for warnings -- see also chk_mnt().
  function fstab_check() {

    local node="$1"
    local mntopts; local cnt

    cnt=$(ssh $node "grep -c '$VOLNAME\s.*\sglusterfs\s' /etc/fstab")
    (( cnt == 0 )) && {
      echo "ERROR on $node: $VOLNAME mount missing in /etc/fstab";
      return 1; }

    (( cnt > 1 )) && {
      echo "ERROR on $node: $VOLNAME appears more than once in /etc/fstab";
      return 1; }
    
    mntopts="$(ssh $node "grep '$VOLNAME\s.*\sglusterfs\s' /etc/fstab")"
    mntopts=${mntopts#* glusterfs }
    # call chk_mnt() and return it's rtncode
    chk_mnt "$mntopts" "$CHK_MNTOPTS" "$CHK_MNTOPTS_WARN"
  }

  ## main 

  echo "--- $node: live $VOLNAME mount options check..."
  live_check $node
  err=$?
  if (( err == 1 )) ; then
    ((errcnt++))
  elif (( err == 2 )) ; then
    ((warncnt++))
  fi

  echo "--- $node: /etc/fstab $VOLNAME mount options check..."
  fstab_check $node
  err=$?
  if (( err == 1 )) ; then
    ((errcnt++))
  elif (( err == 2 )) ; then
    ((warncnt++))
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
# required fstab mount options
CHK_MNTOPTS="$($PREFIX/gen_vol_mnt_options.sh)"
CHK_MNTOPTS="${CHK_MNTOPTS//,/ }" # replace commas with spaces

# required "live" mount options
CHK_MNTOPTS_LIVE="$($PREFIX/gen_vol_mnt_options.sh -l)"
CHK_MNTOPTS_LIVE="${CHK_MNTOPTS_LIVE//,/ }"

# fstab opts to warn user if set
CHK_MNTOPTS_WARN="$($PREFIX/gen_vol_mnt_options.sh -w)"
CHK_MNTOPTS_WARN="${CHK_MNTOPTS_WARN//,/ }"

# "live" opts to warn user if set
CHK_MNTOPTS_LIVE_WARN="$($PREFIX/gen_vol_mnt_options.sh -wl)"
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
