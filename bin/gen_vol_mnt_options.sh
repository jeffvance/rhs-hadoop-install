#!/bin/bash
#
# gen_vol_mnt_options.sh outputs the gluster-fuse mount options that are
# required for hadoop workloads. Earlier versions included entry-timeout=0 and
# attribuite-timeout=0, but now we default these options.

echo 'use-readdirp=no'
