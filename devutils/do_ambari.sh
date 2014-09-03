#!/bin/bash
# script to automate the ambari setup manual steps based on the Install Guide.
# $1= list of nodes, including yarn-master and ambari nodes. If empty then
#     the default list of "ambari.hdp yarn.hdp rhs-1.hdp rhs-2.hdp" is assumed.
#
NODES="$@"
DEFLT_NODES='ambari.hdp yarn.hdp rhs-1.hdp rhs-2.hdp'
echo

if [[ -z "$NODES" ]] ; then
  echo "Using default nodes: $DEFLT_NODES"
  read -p "Continue? [Y|n] " yn
  if [[ "$yn" == "n" || "$yn" == "no" || "$yn" == "N" ]] ; then
    exit 1
  fi
  NODES="$DEFLT_NODES"
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
      subscription-manager register --username jvance@redhat.com --password redhat --force
      subscription-manager attach --auto
      (( $? != 0 )) && subscription-manager attach --auto
      (( $? != 0 )) && subscription-manager attach --auto
      (( $? != 0 )) && {
	echo "******ERROR: 3 attempts to attach --auto failed!";
	exit 1; }
      subscription-manager repos --disable '*'
      subscription-manager repos --enable=rhel-6-server-rpms --enable=rhs-big-data-3-for-rhel-6-server-rpms --enable=rhs-3-for-rhel-6-server-rpms --enable=rhel-scalefs-for-rhel-6-server-rpms

      # create hadoop users on all nodes except for the ambari server
      if [[ ! "$node" =~ ambari ]] ; then
	echo
	echo '---- add hadoop users...'
	groupadd hadoop -g 590
	useradd -u 590 ambari-qa -g hadoop
	useradd -u 591 mapred -g hadoop
	useradd -u 592 yarn -g hadoop
	useradd -u 593 hbase -g hadoop
	useradd -u 594 hcat -g hadoop
	useradd -u 595 hive -g hadoop
	useradd -u 596 oozie -g hadoop
	useradd -u 597 zookeeper -g hadoop
	useradd -u 598 falcon -g hadoop
	useradd -u 599 tez -g hadoop
      fi
    "
done

echo
echo "---- done"
