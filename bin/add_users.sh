#!/bin/bash
#
# add_users.sh adds the required hadoop users, if they are not already present,
# on this node.
# Note: the hadoop users and group need to have the same UID and GID across
#   all nodes in the storage pool and on the mgmt and yarn-master servers.

# note: all users/owners belong to the hadoop group for now
HADOOP_G='hadoop'
errcnt=0; cnt=0
PREFIX="$(dirname $(readlink -f $0))"

for user in $($PREFIX/gen_users.sh); do
    if ! getent passwd $user >/dev/null ; then
      useradd --system -g $HADOOP_G $user 2>&1
      err=$?
      if (( err == 0 )) ; then
	echo "user $user added with UID=$(id -u $user)"
	((cnt++))
      else
	echo "$(hostname): useradd of $user failed with error $err"
	((errcnt++))
      fi
    fi
done

(( errcnt > 0 )) && exit 1
echo "$cnt new Hadoop users added"
exit 0
