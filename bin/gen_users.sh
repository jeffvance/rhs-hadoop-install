#!/bin/bash
#
# gen_users.sh outputs the required hadoop users. This is the only source for
# these users. No attempt is made to create nor validate these users.

HBASE_U='hbase'
HCAT_U='hcat'
HIVE_U='hive'
MAPRED_U='mapred'
YARN_U='yarn'

echo "$MAPRED_U $YARN_U $HBASE_U $HCAT_U $HIVE_U"
