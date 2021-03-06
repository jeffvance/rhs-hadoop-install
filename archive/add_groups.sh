#!/bin/bash
#
# add_groups.sh adds the required hadoop group (only 1 so far), if it is
# not already present, on this node.
# Note: the hadoop users and group need to have the same UID and GID across
#   all nodes in the storage pool and on the mgmt and yarn-master servers.

HADOOP_G='hadoop'
H_GROUPS="$HADOOP_G" # only one hadoop group for now...
errcnt=0; cnt=0

for grp in $H_GROUPS; do
    if ! getent group $grp >/dev/null ; then
      groupadd --system $grp 2>&1
      err=$?
      if (( err == 0 )) ; then
	echo "group $grp added with GID=$(getent group $grp | cut -d: -f3)"
	((cnt++))
      else
	echo "$(hostname): groupadd of $grp failed with error $err"
	((errcnt++))
      fi
    fi
done

(( errcnt > 0 )) && exit 1
echo "$cnt new Hadoop groups added"
exit 0
