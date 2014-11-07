#!/bin/bash
#
# find_prop_value.sh outputs the value of the supplied property from the passed-
# in *-site file.
# Args: $1=property
#       $2=site file prefix, eg. "core" or "yarn",
#       $3=ambari server url (including :port),
#       $4=ambari admin username:password,
#       $5=(optional) ambari cluster name. If not provided it will be found 
#          with an extra REST call.
#       $6=(optional) site tag (version) If not provided it will be found 
#          with an extra REST call.

# check args
(( $# < 4 || $# > 6 )) && {
  echo "Syntax error: expect 4-6 args: property, site-file-prefix, ambari url:port, ambari-admin-user:password, optional cluster-name, and optional site-tag(version)";
  exit -1; }

PREFIX="$(dirname $(readlink -f $0))"

prop="$1"; site="$2"; url="$3"; userpass="$4"
cluster="$5" # may be blank
tag="$6"     # may be blank

if [[ -z "$cluster" ]] ; then
  cluster="$($PREFIX/find_cluster_name.sh $url "$userpass")" || {
    echo "Could not get cluster name: $cluster"; # contains error msg
    exit 1; }
fi

if [[ -z "$tag" ]] ; then
  tag="$($PREFIX/find_site_tag.sh $site $url "$userpass" $cluster)" || {
    echo "Could not get cluster \"$cluster\" tag for ${site}-site: $tag";
    exit 1; }
fi

# get the property value
val="$(curl "http://$url/api/v1/clusters/$cluster/configurations?type={$site}-site&tag=$tag" -s -H 'X-Requested-By: X-Requested-By' -u $userpass \
    | grep $prop)"
if (( $? != 0 )) || [[ -z "$val" ]] ; then
  echo "ERROR: property \"$prop\" is missing: $val"
  exit 1
fi

# return only the un-quoted value portion
val="${val#*: }"   # just value token
val="${val%,}"     # remove trailing comma
echo "${val//\"/}" # remove quotes

exit 0
