#!/bin/bash
#
# check_vol_mount.sh verifies that each node spanned by the supplied volume
# has the vol mount setup correctly. This include verifying both the "live"
# settings, determined by ps, and the "persistent" settings, defined in
# /etc/fstab.
# Syntax:
#  $1=volume name
#  $2=optional list of nodes to check
#  -q, if specified, means only set the exit code, do not output anything
#
# Assumption: the node running this script has access to the gluster cli unless
#   the nodes spanned by the volume are passed to this script.


# given the passed-in vol mount opts, verify the correct settings. Returns 1 
# for errors, 2 for warnings, and 0 for neither.
# Note: cannot return -1, just in case you were wondering...
function chk_mnt() {

  local opts="$1"; local errcnt=0; local warncnt=0

  if ! grep -wq acl <<<$opts; then
    (( ! QUIET )) && echo "WARN: missing acl mount option"
    ((warncnt++))
  fi
  if ! grep -wq "use-readdirp=no" <<<$opts; then
    echo "ERROR: use-readdirp must be set to 'no'"
    ((errcnt++))
  fi
  if ! grep -wq "attribute-timeout=0" <<<$opts; then
    echo "ERROR: attribute-timeout must be set to zero"
    ((errcnt++))
  fi
  if ! grep -wq "entry-timeout=0" <<<$opts; then
    echo "ERROR: entry-timeout must be set to zero"
    ((errcnt++))
  fi

  (( errcnt > 0 ))  && return 1 # 1 or more errors
  (( warncnt > 0 )) && return 2 # 1 or more warnings
  return 0
}

# check_vol_mnt_attrs: verify that the correct mount settings for VOLNAME have
# been set on this node. This include verifying both the "live" settings,
# determined by ps, and the "persistent" settings, defined in /etc/fstab.
function check_vol_mnt_attrs() {

  local rc; local errcnt=0; local warncnt=0; local cnt; local mntopts

  # live check
  mntopts="$(ps -ef | grep -w "$VOLNAME" | grep -vwE 'grep|-s')"
  mntopts=${mntopts#*glusterfs} # just the opts
  chk_mnt "$mntopts"
  rc=$?
  (( rc == 1 )) && ((errcnt++)) || (( rc == 2 )) && ((warncnt++))

  # fstab check
  cnt=$(grep -c $VOLNAME /etc/fstab)
  if (( cnt == 0 )) ; then
    (( ! QUIET )) && echo "ERROR: $VOLNAME mount missing in /etc/fstab"
    ((errcnt++))
  elif (( cnt > 1 )) ; then
    (( ! QUIET )) && \
	echo "ERROR: $VOLNAME appears more than once in /etc/fstab"
    ((errcnt++))
  else # cnt == 1
    mntopts="$(grep -w $VOLNAME /etc/fstab)"
    mntopts=${mntopts#* glusterfs }
    chk_mnt "$mntopts"
    rc=$?
    (( rc == 1 )) && ((errcnt++)) || (( rc == 2 )) && ((warncnt++))
  fi

  (( errcnt > 0 )) && return 1
  (( ! QUIET )) && \
    echo "$VOLNAME mount setup correctly on $NODE with $warncnt warnings"
  return 0
}


## main ## 

errcnt=0; cnt=0
PREFIX="$(dirname $(readlink -f $0))"
QUIET=0 # false (meaning not quiet)

# parse cmd opts
while getopts ':q' opt; do
    case "$opt" in
      q)
	QUIET=1 # true
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
[[ -z "$NODES" ]] && NODES="$($PREFIX/find_nodes.sh $VOLNAME)" 

for NODE in $NODES; do
    ((cnt++)) # num of nodes
    check_vol_mnt_attrs || ((errcnt++))
done

(( errcnt > 0 )) && exit 1
(( ! QUIET )) && echo \
   "The $cnt nodes spanned by $VOLNAME have the correct vol mount settings"
exit 0
