#!/bin/sh

create_conttainer_executor() {
  rm ${task_cfg}
  touch ${task_cfg} 
  cat <<EOF > ${task_cfg} 
yarn.nodemanager.linux-container-executor.group=hadoop
banned.users=yarn
min.user.id=1000
allowed.system.users=mapred
EOF

}


process_user=yarn
process_group=hadoop
task_controller=/usr/lib/hadoop-yarn/bin/container-executor
task_cfg=/etc/hadoop/conf/container-executor.cfg
create_conttainer_executor
echo "Configuring the Linux Container Executor for Hadoop"
chown root:${process_group} ${task_controller} ; chmod 6050 ${task_controller}
chown root:${process_group} ${task_cfg}
