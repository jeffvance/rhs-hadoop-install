##!/bin/bash
#
# ldap.sh: install and setup the ipa server on the passed-in server node.
# User will never need to know or use the hard-coded password.
# Exits 1 on error; otherwise exits 0.
# Args:
#   1=(required) ldap server node, usually the hadoop mgmt node,
#   2+=(optional) list of additional users to add, eg. "tom sally ed".

PREFIX="$(dirname $(readlink -f $0))"

LDAP_NODE="$1"; shift # ldap server
[[ -z "$LDAP_NODE" ]] && {
  echo "Syntax error: the ldap server node is the first arg and is required";
  exit -1; }

if [[ "$HOSTNAME" == "$LDAP_NODE" ]] ; then # use sub-sell rather than ssh
  ssh='('; ssh_close=')'
else # use ssh to ldap server
  ssh="ssh $LDAP_NODE '"; ssh_close="'"
fi

LDAP_DOMAIN="$(eval "$ssh hostname -d $ssh_close")"
[[ -z "$LDAP_DOMAIN" ]] && LDAP_DOMAIN="$LDAP_NODE"

USERS="$($PREFIX/gen_users.sh)" # required hadoop users
USERS+=" $@" # add any additional passed-in users

GROUPS="$($PREFIX/gen_groups.sh)"

# hard-coded admin user and password
ADMIN='admin'
PASSWD='admin123' # min of 8 chars

# set up ldap on the LDAP_NODE
eval "$ssh 
	yum -y install ipa-server
        err=\$?
	(( err != 0 )) && {
	   echo \"ERROR \$err: yum install ipa-server\"; exit 1; }

	# uninstall ipa-server-install for idempotency
	ipa-server-install --uninstall -U
	ipa-server-install -U --hostname=$LDAP_NODE --realm=HADOOP \
		--domain=$LDAP_DOMAIN --ds-password=$PASSWD \
		--admin-password=$PASSWD
        err=\$?
	(( err != 0 )) && {
	   echo \"ERROR \$err: ipa-server-install\"; exit 1; }
 
	echo $PASSWD | kinit $ADMIN
        err=\$?
	(( err != 0 )) && {
	   echo \"ERROR \$err: kinit $ADMIN\"; exit 1; }

	# add group(s)
	for group in $GROUPS; do
	    ipa group-add \$group --desc \${group}-group
	    err=\$?
	    (( err != 0 )) && {
	      echo \"ERROR \$err: ipa group-add \$group\"; exit 1; }
	done

	# add hadoop users + any extra users
	for user in $USERS; do
	    ipa user-add \$user --first \$user --last \$user 
	    err=\$?
	    (( err != 0 )) && {
		echo \"ERROR \$err: ipa user-add \$user\"; exit 1; }
        done

	# associate users with group(s)
	for group in $GROUPS; do
	    ipa group-add-member \$group --users=${USERS// /,}
	    err=\$?
	    (( err != 0 )) && {
	      echo \"ERROR \$err: ipa group-add-member \$group --users $USERS\";
	     exit 1; }
	done
      $ssh_close"

(( $? != 0 )) && exit 1 # error msg echo'd above
exit 0
