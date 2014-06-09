#!/bin/bash
#
# gen_vol_mnt_options.sh outputs the gluster-fuse mount options that are
# required for hadoop workloads.

echo 'entry-timeout=0,attribute-timeout=0,use-readdirp=no'
