#!/bin/bash
#
# set_vol_perf.sh sets the passed-in volume's options for better hadoop
# performance. This only needs to be done once since the volume is distributed.
#
# Syntax:
#  $1=volume name
#  -q, if specified, means only set the exit code, do not output anything
#
# Assumption: the node running this script contains the glusterfs mount dir.

errcnt=0
PREFIX="$(dirname $(readlink -f $0))"
[[ ${PREFIX##*/} != 'bin' ]] && PREFIX+='/bin'

# set assoc array to desired values for the perf config keys
declare -A VOL_SETTINGS=$($PREFIX/gen_vol_perf_settings.sh)

# parse cmd opts
while getopts ':q' opt; do
    case "$opt" in
      q)
        QUIET=true # else, undefined
        shift
        ;;
      \?) # invalid option
        shift # silently ignore opt
        ;;
    esac
done
VOLNAME="$1"

for setting in ${!VOL_SETTINGS[@]}; do
    val="${VOL_SETTINGS[$setting]}"
    out="$(gluster volume set $VOLNAME $setting $val)"
    err=$?
    [[ -z "$QUIET" ]] && echo "$setting $val: $out"
    ((errcnt+=err))
done

(( errcnt > 0 )) && exit 1
[[ -z "$QUIET" ]] && echo "${#VOL_SETTINGS[@]} volume settings successfully set"
exit 0
