#!/bin/bash
#
# check_vol_perf.sh verifies that the supplied volume is set for the correct
# performance values.
# Syntax:
#   $1=Volume name
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

warncnt=0
VOLINFO_TMPFILE="$(mktemp --suffix '.volinfo')"
TAG='^Options Reconfigured:'
PREFIX="$(dirname $(readlink -f $0))"

source $PREFIX/functions # need vol_exists()

# set assoc array to desired values for the perf config keys
declare -A EXPCT_SETTINGS=$($PREFIX/gen_vol_perf_settings.sh)

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

VOLNAME="$1"
[[ -z "$VOLNAME" ]] && {
  echo "Syntax error: volume name is required";
  exit -1; }

[[ -n "$rhs_node" ]] && rhs_node_opt="-n $rhs_node" || rhs_node_opt=''
[[ -z "$rhs_node" ]] && rhs_node="$HOSTNAME" 
NODES="$($PREFIX/find_nodes.sh $rhs_node_opt $VOLNAME)"

if ! vol_exists $VOLNAME $rhs_node ; then
  echo "ERROR: volume $VOLNAME does not exist"
  exit 1
fi

[[ "$rhs_node" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $rhs_node"

eval "$ssh gluster volume info $VOLNAME 2>&1" >$VOLINFO_TMPFILE
err=$?
if (( err != 0 )) ; then
  echo "ERROR $err: vol info: cannot obtain information for $VOLNAME"
  cat $VOLINFO_TMPFILE # error msg
  exit 1
fi

out="$(sed -n "1,/$TAG/d;s/: /:/;p" $VOLINFO_TMPFILE)" # "setting:value ..."

for key in ${!EXPCT_SETTINGS[@]}; do
    val="${EXPCT_SETTINGS[$key]}"
    setting="$key:$val"
    if ! grep -q "$setting" <<<$out ; then
      echo "WARN: $key not set to \"$val\""
      ((warncnt++))
    fi
done

(( warncnt == 0 )) && echo "All $VOLNAME performance settings are correct"
exit 0
