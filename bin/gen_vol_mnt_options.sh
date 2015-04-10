#!/bin/bash
#
# gen_vol_mnt_options.sh outputs the gluster-fuse mount options that are
# required for hadoop workloads.

# NOTE: we flip-flop on returning entry-timeout=0 and attribute-timeout=0 due 
#   kernel/fuse bugs/issues. We need these values set to 1(default) to get
#   acceptable performance, but due kernel/fuse/ESTALE issues, we have to 
#   temporarily set them to 0, meaning no fuse caching.
# Note: different formats are returned depending on the -l and -w flags.
# Args:
#   -l : return "live" data meaning mount info you find in the /var/run/gluster
#        "state" file. Default is to return mnt format used in /etc/fstab.
#   -w : return mnt options we want to warn about. Default is to return the
#        required mnt format.

LIVE=0 # false
WARN=0 # false

# parse cmd opts
while getopts ':lw' opt; do
    case "$opt" in
      l)
        LIVE=1 # true
        ;;
      w)
        WARN=1 # true
        ;;
      \?) # invalid option
        ;;
    esac
done
shift $((OPTIND-1))

if (( LIVE )) ; then
  (( WARN )) && echo "" || \
	echo "entry_timeout=0.000000 attribute_timeout=0.000000 use_readdirp=0"
else # fstab
  (( WARN )) && echo "" || \
	echo "entry-timeout=0,attribute-timeout=0,use-readdirp=no"
fi
