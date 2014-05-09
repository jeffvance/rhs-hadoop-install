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

for user in $($PREFIX/gen_users.sh); do
    if ! getent passwd $user >/dev/null ; then
      useradd --system -g $HADOOP_G $user 2>&1
      err=$?
      if (( err == 0 )) ; then
	(( ! QUIET )) && echo "user $user added with UID=$(id -u $user)"
	((cnt++))
      else
	(( ! QUIET )) && \
	  echo "$(hostname): useradd of $user failed with error $err"
	((errcnt++))
      fi
    fi
done

(( errcnt > 0 )) && exit 1
(( ! QUIET )) && echo "$cnt new Hadoop users added"
exit 0
