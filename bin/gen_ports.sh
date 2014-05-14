#!/bin/bash
#
# gen_ports.sh outputs a tuple of ports used by gluster, ambari, and potentially
# other hadoop services. The format is: "port#:protocol ...", where port# can be
# a range defined as x-z.

GLUSTER_PORTS='20047-20048:tcp 49152-49170:tcp 111:tcp 111:udp 38465-38467:tcp'
AMBARI_PORTS='8080:tcp 8440-8441:tcp'

#  Default Hadoop Ports used by Hortonworks Hadoop (HDP) are documented here:
#  http://docs.hortonworks.com/HDPDocuments/HDP1/HDP-1.2.1/bk_reference/content/reference_chap2_1.html
#
HADOOP_PORTS='50070:tcp 50470:tcp 8020-9000:tcp 50075:http 50475:https 50010:tcp 50020:tcp 50090:http"

echo "$GLUSTER_PORTS $AMBARI_PORTS $HADOOP_PORTS"
