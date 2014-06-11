##!/bin/bash
#
# ldap-client.sh... ...
# Args:
#   1= IPA SERVER (i.e. mrg41.lab.bos.redhat.com)
#   2= IPA Domain (i.e. lab.bos.redhat.com)
#   3= IPA REALM (i.e. HADOOP)

IPA_SERVER=$1 
IPA_DOMAIN=$2 
IPA_REALM=$3

# Remaining args: IPA Clients 

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

