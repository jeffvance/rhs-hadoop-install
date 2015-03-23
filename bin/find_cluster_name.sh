#!/bin/bash
#
# find_cluster_name.sh outputs the name of the current ambari cluster.
# Args: $1=ambari server url (including http:// or https:// and :port),
#       $2=ambari admin username:password.

# check args
(( $# != 2 )) && {
  echo "Syntax error: expect 2 args: ambari url:port, ambari user:password";
  exit -1; }

url="$1"; userpass="$2"

name="$(curl -s -u $userpass "$url/api/v1/clusters/" | grep cluster_name)"
name="${name%,}"    # remove trailing comma if present
name="${name#*: }"  # extract cluster name value
name="${name//\"/}" # remove double-quotes

[[ -z "$name" ]] && {
  echo "ERROR: cluster name not found"; exit 1; }

echo "$name"
exit 0
