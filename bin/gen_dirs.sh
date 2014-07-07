#!/bin/bash
#
# gen_dirs.sh outputs a tuple of "dir:perms:owner" for each of the required
# hadoop directories.
# Syntax:
# -a, output all dirs -- distributed and local
# -d, output only the distributed dirs, skip local dirs
# -l, output only the local dirs, skip distributed dirs

# parse cmd opts
while getopts ':adl' opt; do
    case "$opt" in
      a) # all dirs
        DIST=true; LOCAL=true
        ;;
      d) # only distributed dirs
        DIST=true # else, undefined
        ;;
      l) # only local dirs
        LOCAL=true # else, undefined
        ;;
      \?) # invalid option
        ;;
    esac
done
shift $((OPTIND-1))

[[ -z "$DIST" && -z "$LOCAL" ]] && {
  echo "Syntax error: -a, -d or -l options are required";
  exit -1; }

[[ -n "$DIST" ]] && \
  echo -n "mapred:0770:mapred mapred/system:0755:mapred tmp:1777:yarn \
user:0755:yarn mr-history:0755:yarn tmp/logs:1777:yarn \
mr-history/tmp:1777:yarn mr-history/done:0770:yarn job-staging-yarn:0770:yarn \
app-logs:1777:yarn apps:0775:hive apps/webhcat:0775:hcat "

[[ -n "$LOCAL" ]] && \
  echo -n "mapredlocal:0755:root "

echo # flush line
