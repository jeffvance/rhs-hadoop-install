#!/bin/bash
#
# ldap_clients.sh... ...
# Args:
#   1= IPA SERVER (i.e. mrg41.lab.bos.redhat.com)
#   2= IPA Domain (i.e. lab.bos.redhat.com)
#   3= IPA REALM (i.e. HADOOP)

IPA_SERVER="$1"; shift
IPA_DOMAIN="$1"; shift
IPA_REALM="$1";  shift
CLIENT_NODES="$@"

### JEFF : Decide how to parameterize these.
### For now, I think its okay to hardcode the values.
ADMIN="admin"
PASSWD="admin123"

# Remaining args: IPA Clients 

echo "***************************************"
echo "RHS LDAP CLIENT SETUP"
echo "server/cli : $IPA_SERVER / $IPA_CLIENTS"
echo "domain : $IPA_DOMAIN"
echo "realm : $IPA_REALM" 
echo "***************************************"

for node in $CLIENT_NODES; do
    ssh $node "
	yum -y install ipa-client
        # uninstall ipa-client-install for idempotency
        ipa-client-install --uninstall -U
        echo "Uninstalled ipa : If there are old cert errors, also run rm -rf /etc/ipa/ca.crt"
        ipa-client-install --enable-dns-updates --domain $IPA_DOMAIN \
		--server $IPA_SERVER --realm $IPA_REALM -p $ADMIN -w $PASSWD -U
        err=\$?
        (( err != 0 )) && {
	  echo "ERROR \$err: ipa-client-install on \$node"; exit 1; }
	"
done

(( $? != 0 )) && exit 1
exit 0
