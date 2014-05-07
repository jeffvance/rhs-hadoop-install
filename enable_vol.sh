#!/bin/bash
#
# enable_vol.sh accepts a volume name, checks the volume mount and each node
# spanned by the volume to be sure they are setup for hadoop workloads, and
# then updates the core-site files, on all nodes, to contain the volume. 
#
# Syntax:
#  $1=volName: gluster volume name
#  $2=vol-mnt-prefix: path of the glusterfs-fuse mount point, eg:
#       /mnt/glusterfs. Note: volume name is appended to this mount point.
#  -y: auto answer "yes" to any prompts
#  --yarn-master: hostname or ip of the yarn-master server (required)
#  --hadoop-mgmt-node: hostname or ip of the hadoop mgmt server (required)
#  --user: ambari admin user name
#  --pass: ambari admin user password
#  --port: ambari port
#
# Assumption: script must be executed from a node that has access to the 
#  gluster cli.

PREFIX="$(dirname $(readlink -f $0))"


## functions ##

source $PREFIX/yesno

# parse_cmd: simple positional parsing. Exits on errors.
# Sets globals:
#   AUTO_YES
#   MGMT_NODE
#   MGMT_PASS
#   MGMT_PORT
#   MGMT_USER
#   VOLMNT
#   VOLNAME
#   YARN_NODE
function parse_cmd() {

  local opts='y'
  local long_opts='yarn-master:,hadoop-mgmt-node:,user:,pass:,port:'
  local errcnt=0

  eval set -- "$(getopt -o $opts --long $long_opts -- $@)"

  while true; do
      case "$1" in
        -y)
          AUTO_YES='y'; shift; continue
        ;;
        --yarn-master)
          YARN_NODE="$2"; shift 2; continue
        ;;
        --hadoop-mgmt-node)
          MGMT_NODE="$2"; shift 2; continue
        ;;
        --user)
          MGMT_USER="$2"; shift 2; continue
        ;;
        --pass)
          MGMT_PASS="$2"; shift 2; continue
        ;;
        --port)
          MGMT_PORT="$2"; shift 2; continue
        ;;
        --)
          shift; break
        ;;
      esac
  done

  VOLNAME="$1"
  VOLMNT="$2"

  # check for required args and options
  [[ -z "$VOLNAME" ]] && {
    echo "Syntax error: volume name is required";
    ((errcnt++)); }
  [[ -z "$VOLMNT" ]] && {
    echo "Syntax error: volume mount path prefix is required";
    ((errcnt++)); }
  [[ -z "$YARN_NODE" || -z "$MGMT_NODE" ]] && {
    echo "Syntax error: both yarn-master and hadoop-mgmt-node are required";
    ((errcnt++)); }

  (( errcnt > 0 )) && exit 1
}

# vol_exists: invokes gluster vol info to see if VOLNAME exists. Exits on
# errors.
# Uses globals:
#   VOLNAME
function vol_exists() {

  local err

  gluster volume info $VOLNAME >& /dev/null
  err=$?
  if (( err != 0 )) ; then
    echo "ERROR $err: vol info error on \"$VOLNAME\", volume may not exits"
    exit 1
  fi
}

# setup_nodes: setup each node for hadoop workloads by invoking
# bin/setup_datanodes.sh. Exits on errors.
# Uses globals:
#   BLKDEVS
#   BRKMNTS
#   MGMT_NODE
#   NODES
#   PREFIX
#   YARN_NODE
function setup_nodes() {

  local i; local err; local errcnt=0; local errnodes=''
  local node; local brkmnt; local blkdev

  for (( i=0; i<${#NODES[@]}; i++ )); do
      node=${NODES[$i]}
      brkmnt=${BRKMNTS[$i]}
      blkdev=${BLKDEVS[$i]}

      scp -r -q $PREFIX/bin $node:/tmp
      ssh $node "/tmp/bin/setup_datanode.sh --blkdev $blkdev \
		--brkmnt $brkmnt \
		--yarn-master $YARN_NODE \
		--hadoop-mgmt-node $MGMT_NODE"
      err=$?
      if (( err != 0 )) ; then
        echo "ERROR $err: setup_datanode failed on $node"
        errnodes+="$node "
        ((errcnt++))
      fi
  done

  if (( errcnt > 0 )) ; then
    echo "$errcnt setup node errors on nodes: $errnodes"
    exit 1
  fi
}

# chk_and_fix_nodes: calls check_vol.sh to verify that VOLNAME has been setup
# for hadoop workloads, including each node spanned by the volume. If setup
# issues are detected then the user is optionally prompted to fix the problems.
# Uses globals:
#   AUTO_YES
#   PREFIX
#   VOLNAME
function chk_and_fix_nodes() {

  # verify that the volume is setup for hadoop workload and potentiall fix
  if ! $PREFIX/bin/check_vol.sh $VOLNAME ; then # 1 or more problems
    echo
    echo "One or more nodes spanned by $VOLNAME has issues"
    if [[ -n "$AUTO_YES" ]] || yesno "  Correct above issues? [y|N] " ; then
      setup_nodes
      $PREFIX/bin/set_vol_perf.sh $VOLNAME
    fi
  fi
}


## main ##

errcnt=0

parse_cmd $@

NODES=($($PREFIX/bin/find_nodes.sh $VOLNAME)) # arrays
BRKMNTS=($($PREFIX/bin/find_brick_mnts.sh $VOLNAME))
BLKDEVS=($($PREFIX/bin/find_blocks.sh $VOLNAME))

echo
echo "****NODES=${NODES[@]}"
echo "****BRKMNTS=${BRKMNTS[@]}"
echo

# make sure the volume exists
vol_exists

chk_and_fix_nodes

echo "Enable $VOLNAME in all core-site.xml files..."
$PREFIX/bin/set_glusterfs_uri.sh -h $MGMT_NODE -u $MGMT_USER \
	-p $MGMT_PASS -port $MGMT_PORT $VOLNAME

exit 0
