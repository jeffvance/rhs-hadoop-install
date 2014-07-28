#!/bin/bash
# script to automate the ambari setup manual steps based on the Install Guide.
# $1= list of nodes, includeing yarn-master and ambari nodes. If empty then
#     the default list of "ambari.hdp yarn.hdp rhs-1.hdp rhs-2.hdp" is assumed.
#
NODES="$1"
echo

if [[ -z "$NODES" ]] ; then
  echo "Using default nodes: ambari.hdp yarn.hdp rhs-1.hdp rhs-2.hdp"
  read -p "Continue? [Y|n] " yn
  if [[ "$yn" == "n" || "$yn" == "no" || "$yn" == "N" ]] ; then
    exit 1
  fi
  NODES='ambari.hdp yarn.hdp rhs-1.hdp rhs-2.hdp'
fi

for node in $NODES; do
    echo
    echo "**** node: $node ****"
    ssh $node "
      echo '---- wget 69.pem and 186.pem...'
      cd /etc/pki/product/
      wget \
	http://ooo.englab.brq.redhat.com/~dahorak/RHSS/etc-pki-product/69.pem \
	http://ooo.englab.brq.redhat.com/~dahorak/RHSS/etc-pki-product/186.pem
      sleep 2 # to sycn with wget's async nature...

      echo
      echo '---- sed files...'
      sed -i -e 's,^serverURL=.*,serverURL=https://xmlrpc.rhn.errata.stage.redhat.com/XMLRPC,' /etc/sysconfig/rhn/up2date
      sed -i -e 's,^hostname *=.*,hostname = subscription.rhn.stage.redhat.com,;s,baseurl *=.*,baseurl= http://cdn.stage.redhat.com,' /etc/rhsm/rhsm.conf
      cp /usr/share/rhn/RHNS-CA-CERT /etc/rhsm/ca/redhat-qa.pem

      echo
      echo '---- subscription-manager steps...'
      subscription-manager register --username jvance@redhat.com --password redhat
      subscription-manager attach --auto
      subscription-manager repos --disable '*'
      subscription-manager repos --enable=rhel-6-server-rpms --enable=rhs-big-data-3-for-rhel-6-server-rpms --enable=rhs-3-for-rhel-6-server-rpms --enable=rhel-scalefs-for-rhel-6-server-rpms
    "
done

echo
echo "---- done"
