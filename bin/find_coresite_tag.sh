#!/bin/bash
#
# find_coresite_tag.sh outputs the name of the current tag in the core-site
# config file via a REST API call.
# Args: $1=ambari server url (including :port),
#       $2=ambari admin username:password,
#       $3=(optional) ambari cluster name. If not provided it will be found 
#          with an extra REST call.

# check args
(( $# != 2 && $# != 3 )) && {
  echo "Syntax error: expect 2-3 args: ambari url:port, ambari admin user:password, and optionally ambari cluster name";
  exit -1; }

url="$1"; userpass="$2"; cluster="$3" # may be blank

if [[ -z "$cluster" ]] ; then
  PREFIX="$(dirname $(readlink -f $0))"
  cluster="$($PREFIX/find_cluster_name.sh $url "$userpass")" || {
    echo "Could not get cluster name: $cluster"; # contains error msg
    exit 1; }
fi

tag="$(curl -k -s -u $userpass \
	$url/api/v1/clusters/$cluster?fields=Clusters/desired_configs \
	| sed -n '/"core-site" :/,/"tag" :/p' \
	| tail -n 1 \
	| cut -d \" -f 4)"

[[ -z "$tag" ]] && {
  echo "ERROR: cluster tag not found"; exit 1; }

echo "$tag"
exit 0
