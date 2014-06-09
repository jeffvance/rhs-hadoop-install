#!/bin/bash
#
# gen_ports.sh outputs a string that can be used to assign to an associative
# arrary which contains all ports needed by glusterfs, ambari, and various
# hadoop services/components. The output looks like:
#  "([tcp]="<list of port or port ranges>" [udp]="<list of ports>")
#
# Several intermediate variables are defined to distingush which ports are
# used by which services. If no protocol is specified then tcp is assumed.

#GLUSTER_PORTS='20047-20048 49152-49170 111 111:udp 38465-38467' # vers 3.4
GLUSTER_PORTS='111 111:udp 24007 24009-24108 34865-34867 50152-50251' # ver 3.6
AMBARI_PORTS='8080 8440-8441'
AMBARI_CLIENT_PORT='8670'

# default hadoop ports used by Hortonworks Hadoop (HDP) are documented here:
# http://docs.hortonworks.com/HDPDocuments/HDP1/HDP-1.2.1/bk_reference/content/reference_chap2_1.html
#HADOOP_PORTS='50070 50470 8020-9000 50075 50475 50010 50020 50090'
YARN_PORTS='8030 8031 8032 8033 8040 8041 8042 8088'
ZOOKEEPER_PORTS='2181 2888 3888 8019 9010'
MAPREDUCE_PORTS='19888 10020 50030 8021 50060 8010'
NAMENODE_PORTS='8020 9000 50070 50470 50090 50010 50020 50075 8010 50475 8480 8485'

HADOOP_PORTS="$YARN_PORTS $ZOOKEEPER_PORTS $MAPREDUCE_PORTS $NAMENODE_PORTS"
ALL_PORTS="$GLUSTER_PORTS $AMBARI_PORTS $AMBARI_CLIENT_PORT $HADOOP_PORTS"
declare -A PORTS=()

# assign assoc array
for port in $ALL_PORTS; do
    proto=${port#*:} # == port num if no proto defined
    port=${port%:*}  # can include port range
    [[ "$proto" == "$port" ]] && proto='tcp' # default protocol
    port=${port/-/:} # use iptables range syntax
    PORTS[$proto]+="$port "
done

# output assoc array string
echo -n '('
for proto in ${!PORTS[@]}; do
    echo -n "[$proto]=\"${PORTS[$proto]}\" "
done
echo ')' # flush
