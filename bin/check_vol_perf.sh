#!/bin/bash
#
# check_vol_perf.sh verifies that the supplied volume is set for the correct
# performance values.
# Syntax:
#  $1=Volume name
#  -q, if specified, means only set the exit code, do not output anything
#
# Assumption: the node running this script has access to the gluster cli.
#

errcnt=0
VOLINFO_TMPFILE="$(mktemp --suffix '.volinfo')"
LAST_N=3 # tail records containing vol settings (vol info cmd)
TAG='Options Reconfigured:'
PREFETCH='performance.stat-prefetch'
EAGERLOCK='cluster.eager-lock'
QUICKREAD='performance.quick-read'
# set assoc array to desired values for the perf config keys
declare -A settings=([$PREFETCH]='off' \
                     [$EAGERLOCK]='on' \
                     [$QUICKREAD]='off')

# parse cmd opts
while getopts ':q' opt; do
    case "$opt" in
      q)
	quiet=true  # else, undefined
        shift
	;;
      \?) # invalid option
	shift # silently ignore opt
	;;
    esac
done
VOLNAME="$1"

gluster volume info $VOLNAME >$VOLINFO_TMPFILE 2>&1
err=$?
if (( err != 0 )) ; then
  [[ -z "$quiet" ]] && \
    echo "vol info error $err: cannot obtain performance settings for $VOLNAME"
  exit 2
fi
out="$(sed -e "1,/$TAG/d" $VOLINFO_TMPFILE)" # output from tag to eof
out="${out//: /:}"

for setting in $out ; do # "perf-key:value" list
    k=${setting%:*} # strip off the value part
    v=${setting#*:} # strip off the key part
    if [[ "$v" != "${settings[$k]}" ]] ; then
      [[ -z "$quiet" ]] && \
	echo "WARN: $k set to \"$v\", expect \"${settings[$k]}\""
      ((errcnt++))
    fi
done

(( errcnt != 0 )) && exit 1
[[ -z "$quiet" ]] && echo "All $VOLNAME performance settings are set correctly"
exit 0
