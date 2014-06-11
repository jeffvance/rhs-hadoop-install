#!/bin/bash
#
# ldap_clients.sh: install and setup the ipa client on the passed-in nodes
# for the passed-in ldap/ipa server. Exits 1 on errors; otherwise exits 0.
# Args:
#   1=(required) ldap/ipa-server,
#   2+=(required) list of client nodes.

IPA_SERVER="$1"; shift
CLIENT_NODES="$@"

[[ -z "$IPA_SERVER" ]] && {
  echo "Syntax error: ldap-ipa server is the 1st arg and is required";
  exit -1; }
[[ -z "$CLIENT_NODES" ]] && {
  echo "Syntax error: client nodes are the 2nd arg and are required";
  exit -1; }

IPA_DOMAIN="$(ssh $IPA_SERVER "hostname -d")"
[[ -z "$IPA_DOMAIN ]] && IPA_DOMAIN="$IPA_SERVER"

IPA_REALM='HADOOP' # hard-coded

# hard-code ldap/ipa admin user and password
ADMIN="admin"
PASSWD="admin123"

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
        echo "Uninstalled ipa: If there are old cert errors, also run rm -rf /etc/ipa/ca.crt"
        ipa-client-install -U --enable-dns-updates --domain $IPA_DOMAIN \
		--server $IPA_SERVER --realm $IPA_REALM -p $ADMIN -w $PASSWD
        err=\$?
        (( err != 0 )) && {
	  echo "ERROR \$err: ipa-client-install on \$node"; exit 1; }
	"
done

(( $? != 0 )) && exit 1
exit 0
