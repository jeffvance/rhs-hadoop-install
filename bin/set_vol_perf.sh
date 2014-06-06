#!/bin/bash
#
# set_vol_perf.sh sets the passed-in volume's options for better hadoop
# performance. This only needs to be done once since the volume is distributed.
# However note: when the yarn-master node is glusterfs-fuse mounted to the
#   volume the volume set commands fail with this error: "One or more connected 
#   clients cannot support the feature being set. These clients need to be
#   upgraded or disconnected before running this command again" Un-mounting the
#   volume on the yarn-master fixes the problem.
#
# Syntax:
#   $1=volume name (required).
#   -n=any storage node. Optional, but if not supplied then localhost must be a
#      storage node.

PREFIX="$(dirname $(readlink -f $0))"

source $PREFIX/functions # need vol_exists()

# set assoc array to desired values for the perf config keys
declare -A VOL_SETTINGS=$($PREFIX/gen_vol_perf_settings.sh)

# parse cmd opts
while getopts ':n:' opt; do
    case "$opt" in
      n)
        rhs_node="$OPTARG"
        ;;
      \?) # invalid option
        ;;
    esac
done
shift $((OPTIND-1))
VOLNAME="$1"
[[ -z "$rhs_node" ]] && rhs_node="$HOSTNAME"

[[ -z "$VOLNAME" ]] && {
  echo "Syntax error: volume name is required";
  exit -1; }

vol_exists $VOLNAME $rhs_node || {
  echo "ERROR: volume $VOLNAME does not exist";
  exit 1; }

cmd=''
for setting in ${!VOL_SETTINGS[@]}; do
    val="${VOL_SETTINGS[$setting]}"
    cmd+="gluster volume set $VOLNAME $setting $val; "
done

[[ "$rhs_node" == "$HOSTNAME" ]] && { ssh=''; ssh_close=''; } \
				 || { ssh="ssh $rhs_node '"; ssh_close="'"; }
out="$(eval "$ssh $cmd $ssh_close" 2>&1)"
err=$?
if (( err != 0 )) ; then
  echo -e "ERROR $err: $cmd:\n$out"
  exit 1
fi

echo "$cmd successful"
exit 0
