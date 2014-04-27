#!/bin/bash
#
# gen_gluster_ports.sh outputs a tuple of ports used by gluster and ambari. The
# format is: "port#:protocol ...", where port# can be a range defined as x-z.

echo "20047-20048:tcp 49152-49170:tcp 111:tcp 111:udp 38465-38467:tcp"
