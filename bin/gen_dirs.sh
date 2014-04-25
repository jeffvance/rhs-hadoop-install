#!/bin/bash
#
# gen_dirs.sh outputs a tuple of "dir:perms:owner" for each of the required
# hadoop directories. This is the only source for these directories. No attempt
# is made to create these directories.

echo "mapred:0770:mapred mapred/system:0755:mapred tmp:1777:yarn \
user:0775:yarn mr-history:0755:yarn tmp/logs:1777:yarn \
mr-history/tmp:1777:yarn mr-history/done:0770:yarn job-staging-yarn:0770:yarn \
app-logs:1777:yarn hbase:0770:hbase apps:0775:hive apps/webhcat:0775:hcat"
