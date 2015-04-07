#!/bin/bash
#
# gen_vol_mnt_options.sh outputs the gluster-fuse mount options that are
# required for hadoop workloads (can be empty, "", meaning there are no required
# fuse mount options). There is a script option (-w) that will output the fuse
# mount options that, if present, generate a warning. Live (-l) or non-live
# (fstab) formats are returned.

# NOTE: we flip-flop on returning entry-timeout=0 and attribute-timeout=0 due 
#   kernel/fuse bugs/issues. We need these values set to 1(default) to get
#   acceptable performance, but due kernel/fuse/ESTALE issues, we have to 
#   temporarily set them to 0, meaning no fuse caching. As of Apr 2015 we are
#   returning "" for required fuse mount options (meaning there are no required
#   volume mount options), and "*-timeout=0" for warnings.
# Args:
#   -l : return output consistent with what is found in the /var/run/gluster
#        "state" file. Otherwise, return output consistent with the contents of
#	 /etc/fstab.
#   -w : return mnt options we want to warn about. The output is formated based
#	 on the whether or not -l was supplied. Default is to return the
#        required mnt options.

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

if (( LIVE )) ; then # return output consistent with gluster state format
  (( WARN )) && \
    echo 'entry_timeout=0.000000 attribute_timeout=0.000000' ||
    echo 'use_readdirp=0' # required
else # return output consistent with fstab format
  (( WARN )) && \
    echo 'entry-timeout=0,attribute-timeout=0' ||
    echo 'use-readdirp=no' # required
fi
