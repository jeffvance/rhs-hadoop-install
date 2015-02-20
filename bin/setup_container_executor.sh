#!/bin/sh
#
# setup_container_executor.sh may overwrite this storage node's (localhost's)
# hadoop specific config files for multi tennancy, depending on whether the
# container-executor.cfg file has been modified (based on md5sum). In all cases
# the container cfg files are set to be owned by root and have perms as defined
# below. Exits with 1 for errors, else 0.

create_file=1 # true
errcnt=0
banned_user='yarn'
allowed_users='mapred,ambari_qa' # comma separated list
process_group='hadoop'
perms=6050 # setuid and setgid bits are set
task_controller='/usr/lib/hadoop-yarn/bin/container-executor'
path_task_cfg='/etc/hadoop/conf'
task_cfg="$path_task_cfg/container-executor.cfg"

# The md5 of the container config file is hard-coded here. The reason is so 
# that we don't overwrite a customer's custom container-executor file, which,
# if done, could create security issues.
# Note: if Hortornworks (or anyone) changes container-executor.cfg the md5 sum
#   will also change and this script will not work as designed!
MD5SUM='8afd041c79a90945ebfdd10ccbc43d9d'


function create_container_executor() {
  cat <<EOF >$task_cfg
yarn.nodemanager.linux-container-executor.group=$process_group
banned.users=$banned_user
min.user.id=1000
allowed.system.users=$allowed_users
EOF

}

## main ##

# get the md5 of the current container-executor file
if [[ -f $task_cfg ]] ; then
  echo "$HOSTNAME: $task_cfg exists..."
  curr_md5="$(md5sum $task_cfg)" # "hash filename"
  curr_md5="${curr_md5%% *}"     # just hash
  if [[ "$curr_md5" != "$MD5SUM" ]] ; then
    echo "$task_cfg has been previously modified and will not be over-written;"
    echo "however, the owner and permissions of the file may still be set."
    echo "Current md5 hash: $curr_md5, original md5: $MD5SUM"
    create_file=0 # false
  else
    echo "$task_cfg file will be over-written..."
  fi
elif [[ -d "$path_task_cfg" ]] ; then
  echo "$HOSTNAME: $task_cfg file does not exist, it will be created..."
else
  echo "ERROR: $HOSTNAME: $path_task_cfg does not exist or is not a directory"
  exit 1
fi

echo "$HOSTNAME: configuring the Linux Container Executor for Hadoop"
(( create_file )) && create_container_executor
chown root:$process_group $task_controller || ((errcnt++))
chmod $perms $task_controller || ((errcnt++))

echo "$HOSTNAME: changing owner on $task_cfg"
chown root:$process_group $task_cfg || ((errcnt++))

(( errcnt > 0 )) && exit 1
exit 0
