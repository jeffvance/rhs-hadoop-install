#!/bin/bash
#
# gen_req_gluster_mnt.sh outputs the gluster-fuse mount options that are required
# for hadoop workloads. There is a companion gen_opt_gluster_mnt.sh that handles
# optional/recommended gluster-fuse mount options.

echo 'entry-timeout=0,attribute-timeout=0,use-readdirp=no'
