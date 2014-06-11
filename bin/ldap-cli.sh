##!/bin/bash
#
# ldap.sh... ...
# User will never need to know or use the hard-coded password.
# Exits 1 on error; otherwise exits 0.
# Args:
#   1=hadoop mgmt-node, will be used as the ldap server (required)
#   2+=list of additional users to add, eg. "tom sally ed", (optional)

PREFIX="$(dirname $(readlink -f $0))"

IPA_SERVER=$1 #mrg10.lab.bos.redhat.com
IPA_DOMAIN=$2 # lab.bos.redhat.com
IPA_REALM=$3

echo "***************************************"
echo "RHS LDAP CLIENT SETUP"
echo "server/cli : $IPA_SERVER / $IPA_CLIENTS"
echo "domain : $IPA_DOMAIN"
echo "realm : $IPA_REALM" 
echo "***************************************"

eval "$ssh 
      yum -y install ipa-client &&
      for i in {3..$#}
      do
         echo -n \"$i\"
         ssh \$i \"ipa-client-install --enable-dns-updates --domain $IPA_DOMAIN \
         --server $IPA_SERVER --realm \" &&                
      done &&
      $ssh_close"

(( $? != 0 )) && exit 1

