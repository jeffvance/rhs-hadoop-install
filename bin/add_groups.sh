#!/bin/bash
#
# add_groups.sh adds the required hadoop group (only 1 so far), if it is
# not already present, on this node.
# Note: the hadoop users and group need to have the same UID and GID across
#   all nodes in the storage pool and on the mgmt and yarn-master servers.
#
# Syntax:
#  -q, if specified, means only set the exit code, do not output anything

HADOOP_G='hadoop'
GROUPS="$HADOOP_G" # only one hadoop group for now...
errcnt=0; cnt=0

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

PREFIX="$(dirname $(readlink -f $0))"
[[ ${PREFIX##*/} != 'bin' ]] && PREFIX+='/bin'

for grp in $GROUPS; do
    if ! getent group $grp >/dev/null ; then
      groupadd --system $grp 2>&1
      err=$?
      if (( err == 0 )) ; then
	[[ -z "$QUIET" ]] && \
	  echo "group $grp added with GID=$(getent group $grp | cut -d: -f3)"
	((cnt++))
      else
	[[ -z "$QUIET" ]] && \
	  echo "$(hostname): groupadd of $grp failed with error $err"
	((errcnt++))
      fi
    fi
done

(( errcnt > 0 )) && exit 1
[[ -z "$QUIET" ]] && echo "$cnt new Hadoop groups added"
exit 0
