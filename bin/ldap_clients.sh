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

CERT_FILE='/etc/ipa/ca.crt'
errcnt=0

# before adding clients, first check that no previous cert exists
for node in $CLIENT_NODES; do
    ssh $node "
	if [[ -f $CERT_FILE ]] ; then
	  echo \"ERROR: cert file $CERT_FILE exists on \$node\"
	  echo \"This file needs to be deleted before the ipa client on \$node can be configured.\"
          exit 1
	fi
        exit 0
    "
    (( $? != 0 )) && ((errcnt++))
done
(( errcnt > 0 )) && exit 1 # don't install the ipa client

# now do the client install
err=0
for node in $CLIENT_NODES; do
    ssh $node "
	yum -y install ipa-client
        # uninstall ipa-client-install for idempotency
        ipa-client-install --uninstall -U
        ipa-client-install -U --enable-dns-updates --domain $IPA_DOMAIN \
		--server $IPA_SERVER --realm $IPA_REALM -p $ADMIN -w $PASSWD
        err=\$?
        (( err != 0 )) && {
	  echo "ERROR \$err: ipa-client-install on \$node"; exit \$err; }
    "
    err=$?
    (( err != 0 )) && break
done

exit $err
