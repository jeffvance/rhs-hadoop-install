#!/bin/bash
#
# find_site_tag.sh outputs the name of the current tag in the supplied site
# config file via a REST API call.
# Args: $1=site file prefix, eg. "core" or "yarn",
#       $2=ambari server url (including http:// or https:// and :port),
#       $3=ambari admin username:password,
#       $4=(optional) ambari cluster name. If not provided it will be found 
#          with an extra REST call.

# check args
(( $# != 3 && $# != 4 )) && {
  echo "Syntax error: expect 3-4 args: site-file-prefix, ambari url:port, ambari admin user:password, and optionally ambari cluster name";
  exit -1; }

site="$1"; url="$2"; userpass="$3"; cluster="$4" # may be blank

if [[ -z "$cluster" ]] ; then
  PREFIX="$(dirname $(readlink -f $0))"
  cluster="$($PREFIX/find_cluster_name.sh $url "$userpass")" || {
    echo "Could not get cluster name: $cluster"; # contains error msg
    exit 1; }
fi

tag="$(curl -s -u $userpass \
	$url/api/v1/clusters/$cluster?fields=Clusters/desired_configs \
	| sed -n "/\"${site}-site\" :/,/\"tag\" :/p" \
	| tail -n 1 \
	| cut -d \" -f 4)"

[[ -z "$tag" ]] && {
  echo "ERROR: cluster \"$cluster\" ${site}-site tag not found"; exit 1; }

echo "$tag"
exit 0
