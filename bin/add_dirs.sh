#!/bin/bash
#
# add_dirs.sh adds the required, distributed hadoop directories and assigns the
# correct perms and owners. This only needs to be done once since the dirs are
# distributed by adding them to the glusterfs mount dir, which is required.
# Note: the hadoop users and group need to have the same UID and GID across
#   all nodes in the storage pool and on the mgmt and yarn-master servers.
#
# Syntax:
#  $1=gluster mount path (required)
#  -q, if specified, means only set the exit code, do not output anything
#
# Assumption: the node running this script contains the glusterfs mount dir.

errcnt=0; cnt=0
HADOOP_G='hadoop'

# parse cmd opts
while getopts ':q' opt; do
    case "$opt" in
      q)
        QUIET=true # else, undefined
        shift
        ;;
      \?) # invalid option
        shift # silently ignore opt
        ;;
    esac
done

GLUSTER_MNT="$1"
[[ -z "$GLUSTER_MNT" ]] && {
  echo "ERROR: gluster mount path is required";
  exit -1; }
[[ ! -d "$GLUSTER_MNT" ]] && {
  echo "ERROR: $GLUSTER_MNT is not a directory";
  exit -1; }

PREFIX="$(dirname $(readlink -f $0))"

for tuple in $($PREFIX/gen_dirs.sh); do
    dir="$GLUSTER_MNT/${tuple%%:*}"; let fill=(32-${#dir})
    dir+="$(printf ' %.0s' $(seq $fill))" # left-justified for nicer output
    perm=${tuple%:*}; perm=${perm#*:}
    owner=${tuple##*:}

    mkdir -p $dir 2>&1 \
    && chmod $perm $dir 2>&1 \
    && chown $owner:$HADOOP_G $dir 2>&1
    err=$?

    if (( err == 0 )) ; then
      [[ -z "$QUIET" ]] && echo "$dir created/updated with perms $perm"
      ((cnt++))
    else
      [[ -z "$QUIET" ]] && \
	  echo "$(hostname): creation of dir $dir failed with error $err"
      ((errcnt++))
    fi
done

(( errcnt > 0 )) && exit 1
[[ -z "$QUIET" ]] && echo "$cnt new Hadoop directories added/updated"
exit 0
