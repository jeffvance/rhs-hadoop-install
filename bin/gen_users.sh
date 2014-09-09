#!/bin/bash
#
# gen_users.sh outputs the required hadoop users. This is the only source for
# these users. No attempt is made to create nor validate these users.

echo "mapred yarn hcat hive ambari-qa hbase tez zookeeper oozie falcon"
