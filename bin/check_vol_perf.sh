#!/bin/bash
#
# check_vol_perf.sh verifies that the supplied volume is set for the correct
# performance values.
# Syntax:
#   $1=Volume name
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.
#   -q=only set the exit code, do not output anything

warncnt=0
QUIET=0 # false (meaning not quiet)
VOLINFO_TMPFILE="$(mktemp --suffix '.volinfo')"
LAST_N=3 # tail records containing vol settings (vol info cmd)
TAG='Options Reconfigured:'
LOCALHOST="$(hostname)"
PREFIX="$(dirname $(readlink -f $0))"

source $PREFIX/functions # need vol_exists()

# set assoc array to desired values for the perf config keys
declare -A EXPCT_SETTINGS=$($PREFIX/gen_vol_perf_settings.sh)

# parse cmd opts
while getopts ':qn:' opt; do
    case "$opt" in
      n)
        rhs_node="$OPTARG"
        ;;
      q)
	QUIET=1 # true
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
[[ -z "$rhs_node" ]] && rhs_node="$LOCALHOST" 
NODES="$($PREFIX/find_nodes.sh $rhs_node_opt $VOLNAME)"

if ! vol_exists $VOLNAME $rhs_node ; then
  echo "ERROR: volume $VOLNAME does not exist"
  exit 1
fi

[[ "$rhs_node" == "$LOCALHOST" ]] && ssh='' || ssh="ssh $rhs_node"
eval "$ssh gluster volume info $VOLNAME >$VOLINFO_TMPFILE 2>&1"
err=$?
if (( err != 0 )) ; then
  echo "ERROR $err: vol info: cannot obtain information for $VOLNAME"
  exit 1
fi

out="$(sed -e "1,/$TAG/d" $VOLINFO_TMPFILE)" # output from tag to eof
out="${out//: /:}" # "key:value" (no space)

for setting in $out ; do
    k=${setting%:*} # strip off the value part
    v=${setting#*:} # strip off the key part
    if [[ "$v" != "${EXPCT_SETTINGS[$k]}" ]] ; then
      (( ! QUIET )) && \
	echo "WARN: $k set to \"$v\", expect \"${EXPCT_SETTINGS[$k]}\""
      ((warncnt++))
    fi
done

(( warncnt > 0 )) && exit 0 # no errors, just warnings
(( ! QUIET )) && echo "All $VOLNAME performance settings are set correctly"
exit 0
