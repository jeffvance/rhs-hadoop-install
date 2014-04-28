#!/bin/bash
#
# gen_ports.sh outputs a tuple of ports used by gluster, ambari, and potentially
# other hadoop services. The format is: "port#:protocol ...", where port# can be
# a range defined as x-z.

GLUSTER_PORTS='20047-20048:tcp 49152-49170:tcp 111:tcp 111:udp 38465-38467:tcp'
AMBARI_PORTS='8080:tcp 8440-8441:tcp'

echo "$GLUSTER_PORTS $AMBARI_PORTS"
