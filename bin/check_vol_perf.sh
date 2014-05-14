#!/bin/bash
#
# check_vol_perf.sh verifies that the supplied volume is set for the correct
# performance values.
# Syntax:
#  $1=Volume name
#  -q, if specified, means only set the exit code, do not output anything
#
# Assumption: the node running this script has access to the gluster cli.

warncnt=0
QUIET=0 # false (meaning not quiet)
VOLINFO_TMPFILE="$(mktemp --suffix '.volinfo')"
LAST_N=3 # tail records containing vol settings (vol info cmd)
TAG='Options Reconfigured:'

PREFIX="$(dirname $(readlink -f $0))"

# set assoc array to desired values for the perf config keys
declare -A EXPCT_SETTINGS=$($PREFIX/gen_vol_perf_settings.sh)

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

VOLNAME="$1"
[[ -z "$VOLNAME" ]] && {
  echo "Syntax error: volume name is required";
  exit -1; }

gluster volume info $VOLNAME >$VOLINFO_TMPFILE 2>&1
err=$?
if (( err != 0 )) ; then
  echo "vol info error $err: cannot obtain performance settings for $VOLNAME"
  exit 2
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
