#!/bin/bash
#
# gen_ports.sh outputs a tuple of ports used by gluster, ambari, and potentially
# other hadoop services. The format is: "port#:protocol ...", where port# can be
# a range defined as x-z.

#GLUSTER_PORTS='20047-20048:tcp 49152-49170:tcp 111:tcp 111:udp 38465-38467:tcp'
GLUSTER_PORTS='111:tcp 111:udp 24007:tcp 24009-24108:tcp 34865-34867:tcp 50152-50251:tcp'
AMBARI_PORTS='8080:tcp 8440-8441:tcp'
AMBARI_CLIENT_PORT='8670:tcp'

# default hadoop ports used by Hortonworks Hadoop (HDP) are documented here:
# http://docs.hortonworks.com/HDPDocuments/HDP1/HDP-1.2.1/bk_reference/content/reference_chap2_1.html
#HADOOP_PORTS='50070:tcp 50470:tcp 8020-9000:tcp 50075:tcp 50475:tcp 50010:tcp 50020:tcp 50090:tcp'
YARN_PORTS='8030:tcp 8031:tcp 8032:tcp 8033:tcp 8040:tcp 8041:tcp 8042:tcp 8088:tcp'
ZOOKEEPER_PORTS='2181:tcp 2888:tcp 3888:tcp 8019:tcp 9010:tcp'
MAPREDUCE_PORTS='19888:tcp 10020:tcp 50030:tcp 8021:tcp 50060:tcp 8010:tcp'
NAMENODE_PORTS='8020:tcp 9000:tcp 50070:tcp 50470:tcp 50090:tcp 50010:tcp 50020:tcp 50075:tcp 8010:tcp'
NAMENODE_PORTS+='50475:tcp 8480:tcp 8485:tcp'


HADOOP_PORTS="$YARN_PORTS $ZOOKEEPER_PORTS $MAPREDUCE_PORTS $NAMENODE_PORTS"

echo "$GLUSTER_PORTS $AMBARI_PORTS $AMBARI_CLIENT_PORT $HADOOP_PORTS"
