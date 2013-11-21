#!/bin/sh
# local	dfs.namenode.name.dir	hdfs:hadoop	drwx______
# local	dfs.datanode.data.dir	hdfs:hadoop	drwx______
# local	$HADOOP_LOG_DIR	hdfs:hadoop	drwxrwxr_x
# local	$YARN_LOG_DIR	yarn:hadoop	drwxrwxr_x
# local	yarn.nodemanager.local_dirs	yarn:hadoop	drwxr_xr_x
# local	yarn.nodemanager.log_dirs	yarn:hadoop	drwxr_xr_x
# local	container_executor	root:hadoop	__Sr_s___
# local	conf/container_executor.cfg	root:hadoop	r________
# hdfs	/	hdfs:hadoop	drwxr_xr_x
# hdfs	/tmp	hdfs:hadoop	drwxrwxrwxt
# hdfs	/user	hdfs:hadoop	drwxr_xr_x
# hdfs	yarn.nodemanager.remote_app_log_dir	yarn:hadoop	drwxrwxrwxt
# hdfs	mapreduce.jobhistory.intermediate_done_dir	mapred:hadoop	drwxrwxrwxt
# hdfs	mapreduce.jobhistory.done_dir	mapred:hadoop	drwxr_x___

yarn_nodemanager_remote_app_log_dir="/tmp/logs"
mapreduce_jobhistory_intermediate_done_dir="/mr_history/tmp"
mapreduce_jobhistory_done_dir="/mr_history/done"
HADOOP_LOG_DIR=${HADOOP_LOG_DIR:-${2}/logs}

#
# the rest of these seem to be outdated.
#
# YARN_LOG_DIR={YARN_LOG_DIR:-${HADOOP_LOG_DIR}}
# yarn.nodemanager.log_dirs={yarn.nodemanager.log_dirs:-$YARN_LOG_DIR}
# yarn_nodemanager_local_dirs=""



if [[ $# -lt 2 ]]
then
  echo
  echo "Usage: $0 glustermount pathToHadoopInstall"
  echo 
  echo "Example: $0 /mnt/gluster /opt/hadoop-2.0.5"
  echo
  exit
fi

setPerms(){
  Paths=("${!1}")
  Perms=("${!2}")
  Root_Path=$3
  for (( i=0 ; i<${#Paths[@]} ; i++ ))
   do
    mkdir -p ${Root_Path}/${Paths[$i]}
    chmod ${Perms[$i]} ${Root_Path}/${Paths[$i]} 
    echo ${Paths[$i]} ${Perms[$i]}
    done 
}

echo "Setting permissions on Gluster Volume located at ${1}"

paths=("/" "/tmp" "/user" "${yarn_nodemanager_remote_app_log_dir}" "${mapreduce_jobhistory_intermediate_done_dir}" "${mapreduce_jobhistory_done_dir}");
perms=(0755 1777 0755 1777 1777 0750 );
setPerms paths[@] perms[@] ${1}

echo "Setting local permissions, using hadoop install ${2}"
paths=(${HADOOP_LOG_DIR});
perms=(1777);
setPerms paths[@] perms[@] ${2}
