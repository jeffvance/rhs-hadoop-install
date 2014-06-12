#!/bin/bash
#
# gen_vol_mnt_options.sh outputs the gluster-fuse mount options that are
# required for hadoop workloads. Earlier versions included entry-timeout=0 and
# attribuite-timeout=0, but now we default these options.
# Note: different options and formats are returned depending on the -l and -w
#   flags.
# Args:
#   -l : return "live" data meaning mount info you find in the /var/run/gluster
#        "state" file. Default is to return mnt options used in /etc/fstab.
#   -w : return mnt options we want to warn about. Default is to return
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

if (( LIVE )) ; then
  (( WARN )) && echo "entry_timeout=0.000000 attribute_timeout=0.000000" || \
	echo "use_readdirp=0"
else # fstab (not live)
  (( WARN )) && echo "entry-timeout=0 attribute-timeout=0" || \
	echo "use-readdirp=no"
fi
