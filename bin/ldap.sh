##!/bin/bash
#
# ldap.sh... ...
# User will never need to know or use the hard-coded password.
# Exits 1 on error; otherwise exits 0.
# Args:
#   1=yarn-master node, will be used as the ldap server (required)
#   2+=list of additional users to add, eg. "tom sally ed", (optional)

PREFIX="$(dirname $(readlink -f $0))"
YARN_NODE="$1"; shift 
[[ "$HOSTNAME" == "$YARN_NODE" ]] && ssh='' || ssh="ssh $YARN_NODE"
USERS="sally" # required hadoop users
### USERS+=" $@" # add any additional passed-in users

YARN_DOMAIN="$(eval "$ssh hostname -d")"


ADMIN='admin'
PASSWD='admin123' # min of 8 chars


echo "YARN server = $YARN_DOMAIN "

# on the server:
eval "$ssh
	yum -y install ipa-server		&& \
	ipa-server-install -U --hostname=$YARN_NODE --realm=HADOOP \
		--domain=$YARN_DOMAIN --ds-password=$PASSWD \
		--admin-password=$PASSWD && \
	echo $PASSWD | kinit $ADMIN && \
        ipa group-add hadoop  --desc="hadoop user"  && \
	for user in $USERS; do
    	    ipa user-add $user
	done					&& \
	ipa group-add-member hadoop --users=${USERS// /,}
"
err=$?
if (( err != 0 )) ; then
  echo "ERROR $err: ipa-server: adding group-users"
  exit 1
fi

# on the clients:
ssh mrg42 "yum -y install ipa-client"
ssh mrg42 "ipa-client-install --enable-dns-updates --domain $YARN_DOMAIN \
	--server $YARN_NODE --realm HADOOP"
