#!/bin/bash
#
# gen_opt_gluster_mnt.sh outputs the gluster-fuse mount options that are optional
# for hadoop workloads. There is a companion gen_req_gluster_mnt.sh that handles
# the required gluster-fuse mount options.
# Note: the _netdev option is high-leve and won't be found in /proc/mounts nor in
#   ps output.

echo 'acl'
