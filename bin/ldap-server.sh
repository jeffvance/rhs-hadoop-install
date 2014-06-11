##!/bin/bash
#
# ldap-server.sh: install and setup the ipa server on the passed-in server
# node, and add the required hadoop group(s), and the required hadoop and
# optional user-supplied users. If the user or group already exists it is not
# added. Currently the ldap-server admin user and password are hard-coded but
# that can be changed in the future. Exits 1 on errors; otherwise exits 0.
# Args:
#   1=(required) ldap server node, usually the hadoop mgmt node,
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
[[ -z "$LDAP_DOMAIN" ]] && LDAP_DOMAIN="$LDAP_NODE"

USERS="$($PREFIX/gen_users.sh)" # required hadoop users
USERS+=" $@" # add any additional passed-in users

GROUPS="$($PREFIX/gen_groups.sh)"

# hard-coded admin user and password
ADMIN='admin'
PASSWD='admin123' # min of 8 chars

# set up ldap on the LDAP_NODE and add users/groups
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

	# add hadoop users + any extra users
	for u in $USERS; do
	    if ! getent passwd \$u >& /dev/null ; then # user does not exist
	      ipa user-add \$u --first \$u --last \$u 
	      err=\$?
	      (( err != 0 )) && {
		echo \"ERROR \$err: ipa user-add \$u\"; exit 1; }
	    fi
        done

	# add group(s) and associate to users
	for g in $GROUPS; do
	    if ! getent group \$g >& /dev/null ; then
	      ipa group-add \$g --desc \${g}-group
	      err=\$?
	      (( err != 0 )) && {
		echo \"ERROR \$err: ipa group-add \$g\"; exit 1; }

	      ipa group-add-member \$g --users=${USERS// /,}
	      err=\$?
	      (( err != 0 )) && {
		echo \"ERROR \$err: ipa group-add-member \$g: users: $USERS\";
		exit 1; }
	    fi
	done
      $ssh_close"

(( $? != 0 )) && exit 1 # error msg echo'd above
exit 0
