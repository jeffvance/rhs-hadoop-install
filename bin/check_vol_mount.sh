#!/bin/bash
#
# check_vol_mount.sh verifies that each node spanned by the supplied volume
# has the vol mount setup correctly. This include verifying both the "live"
# settings, determined by the gluster "state" file, and the "persistent"
# settings, defined in /etc/fstab.
# Exit status 1 indicates one or more errors (and possibly warnings).
# Exit status 2 indicates one or more warnings and no errors.
# Exit status 0 indicates no errors or warnings.
# Syntax:
#   $1=volume name
#   $2=optional list of nodes to check. If omitted the nodes are derived using
#      the -n storage node.
#   -n=any storage node. Optional. If not supplied and $2 (nodes) is supplied
#      then the first $2 node is used as -n. If not supplied and $2 is also not
#      supplied then localhost is assumed for -n.


# chk_mnt: given the passed-in existing vol mount opts and the passed-in
# expected mount options, verify the correct settings. Returns 1 for errors
# and returns 2 for warnings.
# Args:
#  1=current mount options
#  2=expected required mount options (live or fstab)
#  3=expected mount options to warn against (live or fstab)
function chk_mnt() {

  local curr_opts="$1"; local expt_opts="$2"; local warn_opts="$3"
  local errcnt=0; local warncnt=0; local opt

  for opt in $expt_opts; do
      if [[ ! "$curr_opts" =~ "$opt" ]] ; then
	echo "ERROR: required volume mount option \"${opt%=*}\" must be set to \"${opt#*=}\""
	((errcnt++))
      fi
  done

  for opt in $warn_opts; do
      if [[ "$curr_opts" =~ "$opt" ]] ; then
	echo "WARN: volume mount option \"${opt%=*}\" should not be set to \"${opt#*=}\""
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
# in /etc/fstab. Returns 1 if any error is detected. Returns 2 if there are no
# errors but one or more warnings are detected. Returns 0 of there are no errors
# and no warnings.
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
      echo "ERROR: glusterfs process not running. $VOLNAME may not be mounted";
      return 1; }

    # generate gluster state file
    ssh $node "kill -SIGUSR1 $pid"

    # sleep a few seconds to handle the case where occassionally the state
    # file is not created prior to the access attempt
    sleep 3

    # copy state file back to local, expected to be 1 file but could match more
    state_file="$state_file${pid}.dump.[0-9]*" # glob -- don't know full name
    scp $node:$state_file_dir/$state_file /tmp

    # assign exact state file name
    state_file=($(ls -r /tmp/$state_file)) # array in reverse order (new -> old)
    (( ${#state_file[@]} == 0 )) && { # missing glusterdump file
      echo "ERROR: glusterdump state file not generated for PID $pid";
      return 1; }
    state_file="${state_file[0]}" # newest

    # extract mount opts section from state file
    mntopts="$(sed -n "/$section/,/^\[/p" $state_file | tr '\n' ' ')"
    mntopts=${mntopts#*] }  # remove leading section name
    mntopts=${mntopts%  [*} # remove trailing section name

    # verify the current mnt options and return chk_mnts rtncode
    chk_mnt "$mntopts" "$CHK_MNTOPTS_LIVE" "$CHK_MNTOPTS_LIVE_WARN"
  }

  # fstab: secondary function to check the mount options in /etc/fstab.
  # Returns 1 on errors and 2 for warnings -- see also chk_mnt().
  function fstab_check() {

    local node="$1"
    local mntopts; local cnt
    local tmpfstab="$(mktemp --suffix _fstab)"

    # create tmp file containing all non-blank, non-comment records in /etc/fstab
    ssh $node "sed '/^ *#/d;/^ *$/d;s/#.*//' /etc/fstab" >$tmpfstab

    cnt=$(grep -c -E "\s+$VOLMNT\s+glusterfs\s" $tmpfstab)
    if (( cnt != 1 )) ; then
      echo -n "ERROR on $node: $VOLMNT mount "
      (( cnt == 0 )) && 
	echo "missing in /etc/fstab." ||
	echo "appears more than once in /etc/fstab."
      echo "  Expect the following mount options: $CHK_MNTOPTS"
      return 1
    fi
    
    mntopts="$(grep -E "\s+$VOLMNT\s+glusterfs\s" $tmpfstab)"
    mntopts="${mntopts#* glusterfs }"
    mntopts="${mntopts%% *}" # skip runlevels
    # call chk_mnt() and return it's rtncode
    chk_mnt "${mntopts//,/ }" "$CHK_MNTOPTS" "$CHK_MNTOPTS_WARN"
  }

  ## main 

  echo "--- $node: live $VOLNAME mount options check..."
  live_check $node
  err=$?
  (( err == 1 )) && ((errcnt++)) || (( err == 2 )) && ((warncnt++))

  echo "--- $node: /etc/fstab $VOLNAME mount options check..."
  fstab_check $node
  err=$?
  (( err == 1 )) && ((errcnt++)) || (( err == 2 )) && ((warncnt++))

  if (( errcnt > 0 )) ; then
    echo "$VOLNAME mount on $node has errors and needs to be corrected"
    return 1
  else
    echo -n "$VOLNAME mount setup correctly on $node"
    (( warncnt > 0 )) && {
      echo " with warnings"; 
      return 2; }
  fi

  echo # flush
  return 0
}


## main ## 

warncnt=0; errcnt=0; cnt=0
PREFIX="$(dirname $(readlink -f $0))"

# assign all combos of mount options (live, fstab, warn, required)
# required fstab mount options
CHK_MNTOPTS="$($PREFIX/gen_vol_mnt_options.sh)"
CHK_MNTOPTS="${CHK_MNTOPTS//,/ }" # replace commas with spaces
# required "live" mount options
CHK_MNTOPTS_LIVE="$($PREFIX/gen_vol_mnt_options.sh -l)"
# fstab opts to warn user if set
CHK_MNTOPTS_WARN="$($PREFIX/gen_vol_mnt_options.sh -w)"
CHK_MNTOPTS_WARN="${CHK_MNTOPTS_WARN//,/ }" # replace commas with spaces
# "live" opts to warn user if set
CHK_MNTOPTS_LIVE_WARN="$($PREFIX/gen_vol_mnt_options.sh -wl)"

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

NODES="$@" # optional list of nodes

# set default for rhs_node
if [[ -z "$rhs_node" ]] ; then
  [[ -z "$NODES" ]] && rhs_node='' || rhs_node="${NODES%% *}" # first node
fi
[[ -n "$rhs_node" ]] && rhs_node="-n $rhs_node"

# get list of nodes if needed
[[ -z "$NODES" ]] && NODES="$($PREFIX/find_nodes.sh $rhs_node $VOLNAME)" 

# find volume mount
VOLMNT="$($PREFIX/find_volmnt.sh $rhs_node $VOLNAME)"
if (( $? != 0 )) ; then
  echo "ERROR: $VOLNAME may not be mounted. $VOLMNT"
  exit 1
fi

for node in $NODES; do
    ((cnt++)) # num of nodes
    check_vol_mnt_attrs $node
    rtn=$?
    (( rtn == 1 )) && ((errcnt++)) || \
    (( rtn == 2 )) && ((warncnt++))
done

(( errcnt > 0 )) && exit 1

echo "The $cnt nodes spanned by $VOLNAME have the correct volume mount"
(( warncnt > 0 )) && exit 2

exit 0
