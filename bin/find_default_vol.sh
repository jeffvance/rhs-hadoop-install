#!/bin/bash
#
# find_default_vol.sh outputs the name of the default volume. This is the first
# volume appearing in the core-site's "fs.glusterfs.volumes" property. Exits
# with 1 on errors.
# Args: $1=ambari server url (including :port),
#       $2=ambari admin username:password,
#       $3=(optional) ambari cluster name. If not provided it will be found 
#          with an extra REST call.

prop='fs.glusterfs.volumes' # list of 1 or more vols, 1st is default

# check args
(( $# < 2 || $# > 3 )) && {
  echo "Syntax error: expect 2-3 args: ambari-url:port, ambari-admin-user:password, and optional cluster-name";
  exit -1; }

PREFIX="$(dirname $(readlink -f $0))"

url="$1"; userpass="$2"; cluster="$3" # may be blank

if [[ -z "$cluster" ]] ; then
  cluster="$($PREFIX/find_cluster_name.sh $url "$userpass")" || {
    echo "Could not get cluster name: $cluster"; # contains error msg
    exit 1; }
fi

vol="$($PREFIX/find_prop_value.sh $prop core $url $userpass $cluster)"
if (( $? != 0 )) ; then
  echo "ERROR: cannot retrieve the core-site $prop value: $vol"
  exit 1
fi

echo "${vol%%,*}" # 1st or only volname, can be ""
exit 0
