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
[[ -z "$YARN_NODE" ]] && {
  echo "Syntax error: the yarn-master node is the first arg and is required";
  exit -1; }

[[ "$HOSTNAME" == "$YARN_NODE" ]] && ssh='' || ssh="ssh $YARN_NODE"
YARN_DOMAIN="$(eval "$ssh hostname -d")"
[[ -z "$YARN_DOMAIN" ]] && YARN_DOMAIN="$YARN_NODE"

USERS="$($PREFIX/gen_users.sh)" # required hadoop users
USERS+=" $@" # add any additional passed-in users
ADMIN='admin'
PASSWD='admin123' # min of 8 chars

# on the server:
eval "$ssh
	yum -y install ipa-server		  && \
	ipa-server-install -U --hostname=$YARN_NODE --realm=HADOOP \
		--domain=$YARN_DOMAIN --ds-password=$PASSWD \
		--admin-password=$PASSWD && \
	echo $PASSWD | kinit $ADMIN && \
        echo \"hadoop group description\" | ipa group-add hadoop && \
	for user in $USERS; do
            IN=\"$user\"
            set -- \"$IN\"
            IFS=\",\"; declare -a Array=($*)
            u=\"${Array[0]}\"
            f=\"${Array[1]}\"
            l=\"${Array[2]}\"
	    ipa user-add $u --first $f --last $l 
            ipa group-add-member hadoop --users=$u
        done		&& \ "
err=$?
if (( err != 0 )) ; then
  echo "ERROR $err: ipa-server: adding group-users"
  exit 1
fi

# on the clients:
ssh mrg42 "yum -y install ipa-client"
ssh mrg42 "ipa-client-install --enable-dns-updates --domain $YARN_DOMAIN	--server $YARN_NODE --realm HADOOP"
