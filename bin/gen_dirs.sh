#!/bin/bash
#
# gen_dirs.sh outputs a tuple of "dir:perms:owner" for each of the required
# hadoop directories.
# Note: the following users are expected to exist:
#   ambari-qa, falcon, hbase, hcat, hive, mapred, oozie,
#   tez, yarn, zookeeper
# Note: the caller is expected to execute mkdir -p on the returned dirs.
#
# Syntax:
# -a, output all dirs as if all options below were passed.
# -d, output only the distributed dirs.
# -l, output only the local dirs.
# -p, output only the dirs that need to be created/changed as post-processing
#     after Ambari services have been installed and then stopped.

# format: <dir-path>:<perms>:<owner>
local_dirs='mapredlocal:0755:root hadoop/yarn:0755:yarn hadoop/yarn/timeline:0755:yarn'

# the remaining dirs are distributed:
mr_dirs='mapred:0770:mapred mapred/system:0755:mapred mr-history:0755:yarn mr-history/tmp:1777:yarn mr-history/done:0770:yarn'

apps_dirs='app-logs:1777:yarn apps:0775:hive'

user_dirs='user:0755:yarn user/hcat:0755:hcat user/hive:0755:hive user/mapred:0755:mapred user/yarn:0755:yarn'

misc_dirs='tmp:1777:yarn tmp/logs:1777:yarn job-staging-yarn:0770:yarn'

# dirs created after ambari services have been started and then stopped
post_processing_dirs='apps/hbase:0755:hbase apps/hbase/staging:0755:hbase apps/hive:0755:hive apps/hive/warehouse:0755:hive apps/falcon:0755:falcon apps/tez:0755:tez hbase:0755:hbase apps/webhcat:0755:hcat user/ambari-qa:0755:ambari-qa user/oozie:0755:oozie user/oozie/share:0755:oozie zookeeper:0755:zookeeper'


# parse cmd opts
while getopts ':adlp' opt; do
    case "$opt" in
      a) # all dirs
        DIST=true; LOCAL=true; POST=true
        ;;
      d) # only distributed dirs
        DIST=true # else, undefined
        ;;
      l) # only local dirs
        LOCAL=true # else, undefined
        ;;
      p) # only post-processing dirs
        POST=true # else, undefined
        ;;
      \?) # invalid option
        ;;
    esac
done

[[ -z "$DIST" && -z "$LOCAL" && -z "$POST" ]] && {
  echo "Syntax error: -a, -d, -l, or -p option required";
  exit -1; }

dirs=''
[[ -n "$DIST" ]]  && dirs+="$mr_dirs $apps_dirs $user_dirs $misc_dirs "
[[ -n "$POST" ]]  && dirs+="$post_processing_dirs "
[[ -n "$LOCAL" ]] && dirs+="$local_dirs "

echo "$dirs"
