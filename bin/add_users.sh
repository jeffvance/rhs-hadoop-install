#!/bin/bash
#
# add_users.sh adds the required hadoop users, if they are not already present,
# on this node.
# Note: the hadoop users and group need to have the same UID and GID across
#   all nodes in the storage pool and on the mgmt and yarn-master servers.
#
# Syntax:
#  -q, if specified, means only set the exit code, do not output anything

# note: all users/owners belong to the hadoop group for now
HADOOP_G='hadoop'
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

for user in $($PREFIX/gen_users.sh); do
    if ! getent passwd $user >/dev/null ; then
      useradd --system -g $HADOOP_G $user 2>&1
      err=$?
      if (( err == 0 )) ; then
	[[ -z "$QUIET" ]] && echo "user $user added with UID=$(id -u $user)"
	((cnt++))
      else
	[[ -z "$QUIET" ]] && \
	  echo "$(hostname): useradd of $user failed with error $err"
	((errcnt++))
      fi
    fi
done

(( errcnt > 0 )) && exit 1
[[ -z "$QUIET" ]] && echo "$cnt new Hadoop users added"
exit 0
