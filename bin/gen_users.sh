#!/bin/bash
#
# gen_users.sh outputs the required hadoop users. This is the only source for
# these users. No attempt is made to create nor validate these users.

HBASE_U='hbase-n-n'
HCAT_U='hcat-n-n'
HIVE_U='hive-n-n'
MAPRED_U='mapred-n-n'
YARN_U='yarn-n-n'

echo "$MAPRED_U $YARN_U $HBASE_U $HCAT_U $HIVE_U"
