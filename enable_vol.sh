#!/bin/bash
#
# enable_vol.sh accepts a volume name, checks the volume mount and each node
# spanned by the volume to be sure they are setup for hadoop workloads, and
# then updates the core-site files, on all nodes, to contain the volume. 
#
# Syntax:
#  $1=volName: name of the new volume
#  $2=vol-mnt-prefix: path of the glusterfs-fuse mount point, eg:
#       /mnt/glusterfs. Note: volume name is appended to this mount point.
#  --yarn-master: hostname or ip of the yarn-master server
#  --hadoop-mgmt-node: hostname or ip of the hadoop mgmt server
#
# Assumption: script must be executed from a node that has access to the 
#  gluster cli.


## funtions ##

# parse_cmd: simple positional parsing. Exits on errors.
# Sets globals:
#   VOLNAME
#   VOLMNT
#   YARN_NODE
#   MGMT_NODE
function parse_cmd() {

  local long_opts='yarn-master:,hadoop-mgmt-node:'

  eval set -- "$(getopt -o '' --long $long_opts -- $@)"

  while true; do
      case "$1" in
        --yarn-master)
          YARN_NODE="$2"; shift 2; continue
        ;;
        --hadoop-mgmt-node)
          MGMT_NODE="$2"; shift 2; continue
        ;;
        --)
          shift; break
        ;;
      esac
  done

  VOLNAME="$1"
  VOLMNT="$2"

  [[ -z "$VOLNAME" ]] && {
    echo "Syntax error: volume name is required";
    exit -1; }
  [[ -z "$VOLMNT" ]] && {
    echo "Syntax error: volume mount path prefix is required";
    exit -1; }
  [[ -z "$YARN_NODE" || -z "$MGMT_NODE" ]] && {
    echo "Syntax error: both yarn-master and hadoop-mgmt-node are required";
    exit -1; }
}

# chk_vol: invokes gluster vol info to see if VOLNAME exists. Exits on errors.
# Uses globals:
#   VOLNAME
function chk_vol() {

  local err

  gluster volume info $VOLNAME >& /dev/null
  err=$?
  if (( err != 0 )) ; then
    echo "ERROR $err: vol info error on \"$VOLNAME\", volume may not exits"
    exit 1
  fi
}


## main ##

PREFIX="$(dirname $(readlink -f $0))"
errcnt=0

parse_cmd $@

NODES=($($PREFIX/bin/find_nodes.sh $VOLNAME)) # arrays
BRKMNTS=($($PREFIX/bin/find_brick_mnts.sh $VOLNAME))

echo
echo "****NODES=${NODES[@]}"
echo "****BRKMNTS=${BRKMNTS[@]}"
echo

# make sure the volume exists
chk_vol

# verify that the volume is setup for hadoop workload
$PREFIX/bin/check_vol.sh $VOLNAME

exit 0
