##!/bin/bash
#
# ldap.sh...
# Args:
#   1=yarn-master node, will be used as the ldap server (required)
#   2+=list of additional users to add, eg. "tom sally ed", (optional)

YARN_NODE="$1"; shift
PREFIX="$(dirname $(readlink -f $0))"
USERS="$($PREFIX/gen_users.sh)" # required hadoop users
USERS+=" $@" # add any additional passed-in users

# on the server:
ssh $YARN_NODE "
	yum -y install ipa-server
	ipa group-add hadoop # done before adding users
	for user in $USERS; do
    	    ipa user-add $user
	done
	# associate users to the hadoop group
	ipa group-add-member hadoop --users=${USERS// /,}
"

# on the clients:
yum -y install ipa-client
# JAY needs to define the realm
ipa-client-install --enable-dns-updates --domain <yarn-master-hostname> --server ipaserver.example.com --realm EXAMPLE -p host/server.example.com
