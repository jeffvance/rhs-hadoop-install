#!/bin/bash
#
# ldap-server.sh: install and setup the ipa server on the passed-in server
# node, and add the required hadoop group(s), and the required hadoop and
# optional user-supplied users. If the user or group already exists it is not
# added. Currently the ldap-server admin user and password are hard-coded but
# that can be changed in the future. Exits 1 on errors; otherwise exits 0.
# Args:
#   1=(required) ldap/ipa server node, usually the hadoop mgmt node,
#   2+=(optional) list of additional users to add, eg. "tom sally ed".

PREFIX="$(dirname $(readlink -f $0))"

LDAP_NODE="$1"; shift # ldap server
[[ -z "$LDAP_NODE" ]] && {
  echo "Syntax error: the ldap server node is the first arg and is required";
  exit -1; }

if [[ "$HOSTNAME" == "$LDAP_NODE" ]] ; then # use sub-shell rather than ssh
  ssh='('; ssh_close=')'                    # so that a common exit can be used
else # use ssh to ldap server
  ssh="ssh $LDAP_NODE '"; ssh_close="'"
fi

LDAP_DOMAIN="$(eval "$ssh hostname -d $ssh_close")"
[[ -z "$LDAP_DOMAIN" ]] && LDAP_DOMAIN="${LDAP_NODE#*.}" # remove simple host

USERS="$($PREFIX/gen_users.sh)" # required hadoop users
USERS+=" $@" # add any additional passed-in users

GROUPS="$($PREFIX/gen_groups.sh)"

# hard-coded admin user and password
ADMIN='admin'
PASSWD='admin123' # min of 8 chars

# hard-coded realm, i.e. LAB.XYZ.COMPANY.COM
IPA_REALM="$(echo $LDAP_DOMAIN | tr '[:lower:]' '[:upper:]')"

# misc
DFLT_EMAIL='none@none.com'
CERT_FILE='/etc/ipa/ca.crt'

# set up ldap on the LDAP_NODE and add users/groups
err=0
eval "$ssh 
	echo "ipa-server on node: $node"
	if [[ -f $CERT_FILE ]] ; then
	  echo "$CERT_FILE exists thus not proceeding with ipa-server-install"
	else
          if ! rpm -q ipa-server ; then
	    echo "installing ipa-server..."
	    yum -y install ipa-server 2>&1
            err=\$?
	    (( err != 0 )) && {
	      echo \"ERROR \$err: yum install ipa-server\"; exit \$err; }
	  fi
	  ipa-server-install -U --hostname=$LDAP_NODE --realm=$IPA_REALM \
		--domain=$LDAP_DOMAIN --ds-password=$PASSWD \
		--admin-password=$PASSWD 2>&1
          err=\$?
	  (( err != 0 )) && {
	     echo \"ERROR \$err: ipa-server-install\"; exit \$err; }
	fi
 
	echo $PASSWD | kinit $ADMIN 2>&1
        err=\$?
	(( err != 0 )) && {
	   echo \"ERROR \$err: kinit $ADMIN\"; exit \$err; }

	# add hadoop users + any extra users (may already exist)
	for u in $USERS; do
	    if ! getent passwd \$u >& /dev/null ; then # user does not exist
	      ipa user-add \$u --first \$u --last \$u --email $DFLT_EMAIL 2>&1
	      err=\$?
	      (( err != 0 )) && {
		echo \"ERROR \$err: ipa user-add \$u\"; exit \$err; }
	    fi
        done

	# add group(s) and associate to users
	for g in $GROUPS; do
	    if ! getent group \$g >& /dev/null ; then
	      ipa group-add \$g --desc \${g}-group 2>&1
	      err=\$?
	      (( err != 0 )) && {
		echo \"ERROR \$err: ipa group-add \$g\"; exit \$err; }

	      ipa group-add-member \$g --users=${USERS// /,} 2>&1
	      err=\$?
	      (( err != 0 )) && {
		echo \"ERROR \$err: ipa group-add-member \$g: users: $USERS\";
		exit \$err; }
	    fi
	done
      $ssh_close"
err=$?

exit $err
