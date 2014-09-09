#!/bin/bash
#
# add_dirs.sh adds the required hadoop directories and assigns the correct
# permissions and owners on this node (localhost). The caller only needs to
# invoke add_dirs once for the pool when -d (distributed) or -p (post-
# processing) are specified. It needs to be invoked on each node when -l is
# specified.
# Note: the hadoop users and group need to have the same UID and GID across
#   all nodes in the storage pool and on the mgmt and yarn-master servers; 
#   however this script does not check nor enforce this requirement.
#
# Syntax:
#  $1=distributed gluster mount (single) or brick mount(s) (per-node) path 
#     (required).
#  -d=create only the distributed, non-post-processing, dirs
#  -l=create only the local dirs
#  -p=create only the post-processing, distributed dirs.

errcnt=0; cnt=0
HADOOP_G='hadoop'
PREFIX="$(dirname $(readlink -f $0))"

opt="$1" # expected to be -d or -l or -p
shift

MNT="$@" # typically a single mount but can be a list
[[ -z "$MNT" ]] && {
  echo "ERROR: mount path(s) required";
  exit -1; }

if [[ "$opt" != '-d' && "$opt" != '-l' && "$opt" != '-p' ]] ; then
  echo "Syntax error: one of -d, -l, or -p is required"
  exit -1
fi

# test for directory
for dir in $MNT; do
   [[ ! -d $dir ]] && {
	echo "ERROR: $dir is not a directory";
	exit -1; }
done

dirs_to_add="$($PREFIX/gen_dirs.sh $opt)"

for dir in $MNT; do # to handle a list of local mounts
    for tuple in $dirs_to_add; do
	path="$dir/${tuple%%:*}"; let fill=(42-${#path})
	path+="$(printf ' %.0s' $(seq $fill))" # left-justified for nicer output
	perm=${tuple%:*}; perm=${perm#*:}
	owner=${tuple##*:}

	mkdir -p $path 2>&1 \
	  && chmod $perm $path 2>&1 \
	  && chown $owner:$HADOOP_G $path 2>&1
	err=$?

	if (( err == 0 )) ; then
	  echo "$path created/updated with perms $perm"
	  ((cnt++))
	else
	  echo "$(hostname): creation of path $path failed with error $err"
	  ((errcnt++))
	fi
    done
done

(( errcnt > 0 )) && exit 1
echo "$cnt new Hadoop directories added/updated"
exit 0
