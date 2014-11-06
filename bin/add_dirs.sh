#!/bin/bash
#
# add_dirs.sh adds the supplied directories, with the passed-in permissions and
# owners, on this node (localhost). The caller only needs to invoke add_dirs
# once for distributed directors. However, for local dirs add_dirs needs to be
# invoked on each node.
# Note: the hadoop users and group need to have the same UID and GID across
#   all nodes in the storage pool and on the mgmt and yarn-master servers; 
#   however this script does not check nor enforce this requirement.
# Note: the POSIX group is hard-coded to 'hadoop' for now.
#
# Syntax:
#  $1=distributed gluster mount or brick mount path (required).
#  $2-$n=directories to add. Format is: <dirname>:<perms>:<owner> (required).

errcnt=0; cnt=0
HADOOP_G='hadoop'
PREFIX="$(dirname $(readlink -f $0))"

MNT="$1"
[[ -z "$MNT" ]] && {
  echo "ERROR: mount path(s) required";
  exit -1; }
[[ ! -d "$MNT" ]] && {
    echo "ERROR: $MNT is not a directory";
    exit -1; }

shift; DIRS="$@"
[[ -z "$DIRS" ]] && {
  echo "ERROR: list of directories expected. Format: <dir>:<perms>:<owner> ..."
  exit -1; }

# create the dirs
for tuple in $DIRS; do
    path="$MNT/${tuple%%:*}"; let fill=(42-${#path})
    path+="$(printf ' %.0s' $(seq $fill))" # left-justified for nicer output
    perm=${tuple%:*}; perm=${perm#*:}
    owner=${tuple##*:}

    mkdir -p $path 2>&1 &&
	chmod $perm $path 2>&1 &&
	chown $owner:$HADOOP_G $path 2>&1
    err=$?

    if (( err == 0 )) ; then
      echo "$path created/updated with perms $perm"
      ((cnt++))
    else
      echo "$HOSTNAME: creation of path $path failed with error $err"
      ((errcnt++))
    fi
done

(( errcnt > 0 )) && exit 1
echo "$cnt new Hadoop directories added/updated"
exit 0
