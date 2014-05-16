#!/bin/bash
#
# set_vol_perf.sh sets the passed-in volume's options for better hadoop
# performance. This only needs to be done once since the volume is distributed.
# Syntax:
#   $1=volume name (required).
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

errcnt=0
PREFIX="$(dirname $(readlink -f $0))"
QUIET=0 # false (meaning not quiet)
LOCALHOST="$(hostname)"

source $PREFIX/functions # need vol_exists()

# set assoc array to desired values for the perf config keys
declare -A VOL_SETTINGS=$($PREFIX/gen_vol_perf_settings.sh)

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
[[ -z "$rhs_node" ]] && rhs_node="$LOCALHOST"

[[ -z "$VOLNAME" ]] && {
  echo "Syntax error: volume name is required";
  exit -1; }

vol_exists $VOLNAME $rhs_node || {
  echo "ERROR: volume $VOLNAME does not exist";
  exit 1; }

cmd=''
for setting in ${!VOL_SETTINGS[@]}; do
    val="${VOL_SETTINGS[$setting]}"
    cmd+="gluster volume set $VOLNAME $setting $val; "
done

[[ "$rhs_node" == "$LOCALHOST" ]] && ssh='' || ssh="ssh $rhs_node"
out="$(eval "$ssh '$cmd'")"
err=$?
(( ! QUIET )) && echo "$setting $val: $out"
((errcnt+=err))

(( errcnt > 0 )) && exit 1
(( ! QUIET )) && echo "${#VOL_SETTINGS[@]} volume settings successfully set"
exit 0
