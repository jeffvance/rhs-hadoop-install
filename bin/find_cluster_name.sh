#!/bin/bash
#
# find_cluster_name.sh outputs the name of the current ambari cluster.
# Args: $1=ambari server url (including :port),
#       $2=ambari admin username,
#       $3=ambari user password.

# check args
(( $# != 3 )) && {
  echo "Syntax error: expect 3 args: ambari url, ambari admin user, password";
  exit -1; }

url="$1"; user="$2"; pass="$3"
PREFIX="$(dirname $(readlink -f $0))"

name="$(curl -s -u $user:$pass "$url/api/v1/clusters/" | grep cluster_name)"
name="${name%,}"    # remove trailing comma if present
name="${name#*: }"  # extract cluster name value
name="${name//\"/}" # remove double-quotes

[[ -z "$name" ]] && {
  echo "ERROR: cluster name not found"; exit 1; }

echo "$name"
exit 0
