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
[[ -z "$IPA_DOMAIN" ]] && IPA_DOMAIN="${IPA_SERVER#*.}" # remove simple host

IPA_REALM="$(echo $IPA_DOMAIN | tr '[:lower:]' '[:upper:]')"

# hard-code ldap/ipa admin user and password
ADMIN="admin"
PASSWD="admin123"
CERT_FILE='/etc/ipa/ca.crt'

err=0
for node in $CLIENT_NODES; do
    ssh -q $node "
	echo "ipa-client on node: $node"
	if [[ -f $CERT_FILE ]] ; then
	  echo "$CERT_FILE exists thus not proceeding with ipa-client-install"
	else
	  if ! rpm -q ipa-client ; then 
	    echo "installing ipa-client..."
	    yum -y install ipa-client 2>&1
	    err=\$?
	    (( err != 0 )) && {
	      echo \"ERROR \$err: yum install ipa-client\"; exit \$err; }
	  fi
	  # uninstall ipa-client just in case...
	  ipa-client-install -U --uninstall  # ignore error if any
	  # install the ipa client on this node
          ipa-client-install -U --enable-dns-updates --domain $IPA_DOMAIN \
		--server $IPA_SERVER --realm $IPA_REALM -p $ADMIN \
		-w $PASSWD 2>&1
          err=\$?
          (( err != 0 )) && {
	    echo "ERROR \$err: ipa-client-install on $node"; exit \$err; }
	fi
	exit 0
    "
    err=$?
    (( err != 0 )) && break
done

exit $err
