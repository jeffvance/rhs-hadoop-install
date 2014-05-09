#!/bin/bash
#
# add_dirs.sh adds the required hadoop directories and assigns the correct perms
# and owners. This only needs to be done once for the pool when -d is specified.
# It needs to be done per-node if -l is specified.
# Note: the hadoop users and group need to have the same UID and GID across
#   all nodes in the storage pool and on the mgmt and yarn-master servers.
#
# Syntax:
#  $1=distributed (gluster) or brick mount (per-node) path -- required
#  -q, if specified, means only set the exit code, do not output anything
#  -d, output only the distributed dirs, skip local dirs
#  -l, output only the local dirs, skip distributed dirs

errcnt=0; cnt=0
HADOOP_G='hadoop'
PREFIX="$(dirname $(readlink -f $0))"
QUIET=0 # false (meaning not quiet)

# parse cmd opts
while getopts ':qdl' opt; do
    case "$opt" in
      q)
        QUIET=1 # true
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

MNT="$1"
[[ -z "$MNT" ]] && {
  echo "ERROR: mount path is required";
  exit -1; }
[[ ! -d "$MNT" ]] && {
  echo "ERROR: $MNT is not a directory";
  exit -1; }

if [[ -n "$DIST" ]] ; then
  opt='-d'
elif [[ -n "$LOCAL" ]] ; then
  opt='-l'
else
  echo "Syntax error: -d or -l options are required"
  exit -1
fi

for tuple in $($PREFIX/gen_dirs.sh $opt); do
    dir="$MNT/${tuple%%:*}"; let fill=(42-${#dir})
    dir+="$(printf ' %.0s' $(seq $fill))" # left-justified for nicer output
    perm=${tuple%:*}; perm=${perm#*:}
    owner=${tuple##*:}

    mkdir -p $dir 2>&1 \
    && chmod $perm $dir 2>&1 \
    && chown $owner:$HADOOP_G $dir 2>&1
    err=$?

    if (( err == 0 )) ; then
      (( ! QUIET )) && echo "$dir created/updated with perms $perm"
      ((cnt++))
    else
      (( ! QUIET )) && \
	  echo "$(hostname): creation of dir $dir failed with error $err"
      ((errcnt++))
    fi
done

(( errcnt > 0 )) && exit 1
(( ! QUIET )) && echo "$cnt new Hadoop directories added/updated"
exit 0
