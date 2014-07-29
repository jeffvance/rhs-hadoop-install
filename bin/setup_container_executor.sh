#!/bin/sh
#
# setup_container_executor.sh sets up this storage node's (localhost's) hadoop
# specific config files for multi tennancy. Exits with 1 for errors, else 0.
#

function create_container_executor() {
  cat <<EOF >$task_cfg
yarn.nodemanager.linux-container-executor.group=$process_group
banned.users=$process_user
min.user.id=1000
allowed.system.users=mapred
EOF

}

errcnt=0
process_user=yarn
process_group=hadoop
perms=6050
task_controller=/usr/lib/hadoop-yarn/bin/container-executor
task_cfg=/etc/hadoop/conf/container-executor.cfg

echo "Configuring the Linux Container Executor for Hadoop"
create_container_executor

chown root:$process_group $task_controller || ((errcnt++))
chmod $perms $task_controller              || ((errcnt++))
chown root:$process_group $task_cfg        || ((errcnt++))

(( errcnt > 0 )) && exit 1
exit 0
