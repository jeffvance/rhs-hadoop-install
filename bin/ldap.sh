##!/bin/bash
#
# ldap.sh... ...
# User will never need to know or use the hard-coded password.
# Exits 1 on error; otherwise exits 0.
# Args:
#   1=hadoop mgmt-node, will be used as the ldap server (required)
#   2+=list of additional users to add, eg. "tom sally ed", (optional)

PREFIX="$(dirname $(readlink -f $0))"
MGMT_NODE="$1"; shift
[[ -z "$MGMT_NODE" ]] && {
  echo "Syntax error: the yarn-master node is the first arg and is required";
  exit -1; }

if [[ "$HOSTNAME" == "$MGMT_NODE" ]] ; then # use sub-sell rather than ssh
  ssh='('; ssh_close=')'
else # use ssh to mgmt node
  ssh="ssh $MGMT_NODE '"; ssh_close="'"
fi

MGMT_DOMAIN="$(eval "$ssh hostname -d $ssh_close")"
[[ -z "$MGMT_DOMAIN" ]] && MGMT_DOMAIN="$MGMT_NODE"

USERS="$($PREFIX/gen_users.sh)" # required hadoop users
USERS+=" $@" # add any additional passed-in users
ADMIN='admin'
PASSWD='admin123' # min of 8 chars

# on the server:
eval "$ssh 
	yum -y install ipa-server
        err=\$?
	(( err != 0 )) && {
	   echo \"ERROR \$err: yum install ipa-server\"; exit 1; }

	# uninstall ipa-server-install for idempotency
	ipa-server-install --uninstall -U
	ipa-server-install -U --hostname=$MGMT_NODE --realm=HADOOP \
		--domain=$MGMT_DOMAIN --ds-password=$PASSWD \
		--admin-password=$PASSWD
        err=\$?
	(( err != 0 )) && {
	   echo \"ERROR \$err: ipa-server-install\"; exit 1; }
 
	echo $PASSWD | kinit $ADMIN
        err=\$?
	(( err != 0 )) && {
	   echo \"ERROR \$err: kinit $ADMIN\"; exit 1; }

        ipa group-add hadoop --desc hadoop-group
        err=\$?
	(( err != 0 )) && {
	   echo \"ERROR \$err: ipa group-add hadoop\"; exit 1; }

	for user in $USERS; do
	    ipa user-add \$user --first \$user --last \$user 
	    err=\$?
	    (( err != 0 )) && {
		echo \"ERROR \$err: ipa user-add $user\"; exit 1; }
        done

        ipa group-add-member hadoop --users=${USERS// /,}
        err=\$?
	(( err != 0 )) && {
	   echo \"ERROR \$err: ipa group-add-member hadoop --users $USERS\";
	   exit 1; }

      $ssh_close"

(( $? != 0 )) && exit 1 # error msg echo'd above

# on the clients:
ssh mrg42 "yum -y install ipa-client"
ssh mrg42 "ipa-client-install --enable-dns-updates --domain $MGMT_DOMAIN \
	--server $MGMT_NODE --realm HADOOP"
