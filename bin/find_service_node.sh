#!/bin/bash
#
# find_service_node.sh outputs the node name for the requested service via a
# REST API call.
# Args: $1=service name, eg "WEBHCAT",
#       $2=component name, eg "WEBHCAT_SERVER",
#       $3=ambari server full url (including http:// or https:// and :port),
#       $4=ambari admin username:password,
#       $5=(optional) ambari cluster name. If not provided it will be found 
#          with an extra REST call.

# check args
(( $# != 4 && $# != 5 )) && {
  echo "Syntax error: expect 4-5 args: service-name, component-name, ambari-url:port, ambari-admin-user:password, and optionally ambari-cluster-name";
  exit -1; }

service="$1"; component="$2"
url="$3"; userpass="$4"; cluster="$5" # may be blank

if [[ -z "$cluster" ]] ; then
  PREFIX="$(dirname $(readlink -f $0))"
  cluster="$($PREFIX/find_cluster_name.sh $url "$userpass")" || {
    echo "Could not get cluster name: $cluster"; # contains error msg
    exit 1; }
fi

node="$(curl "$url/api/v1/clusters/$cluster/services/$service/components/$component" -s -H 'X-Requested-By: X-Requested-By' -u $userpass \
	| grep host_name)"
(( $? != 0 )) || [[ -z "$node" ]] && {
  echo "$service service not enabled: $node";
  exit 1; }

# extract just the host name value for this service
node="${node#*: }"  # just value token
node="${node%,}"    # remove trailing comma, if any
echo "${node//\"/}" # remove quotes

exit 0
