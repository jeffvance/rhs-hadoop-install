#!/bin/bash
#
# enable_vol.sh accepts a volume name, checks the volume mount and each node
# spanned by the volume to be sure they are setup for hadoop workloads, and
# then updates the core-site files on all nodes to contain the volume. 
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

  local opts=''
  local long_opts='yarn-master:,hadoop-mgmt-node:'

  eval set -- "$(getopt -o $opts --long $long_opts -- $@)"

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
    echo "ERROR $err: volume \"$VOLNAME\" error, volume may not exits"
    exit 1
  fi
}

# chk_nodes: verify that each node that will be spanned by the new volume is 
# prepped for hadoop workloads by invoking bin/check_node.sh. Exits on errors.
# Uses globals:
#   NODES
#   BRKMNTS
#   PREFIX
# Side effect: all scripts under bin/ are copied to each node.
function chk_nodes() {

  local i; local node
  local err; local out

  # verify that each node is prepped for hadoop workloads
  for (( i=0; i<${#NODES[@]}; i++ )); do
      node=${NODES[$i]}
      scp -r -q $PREFIX/bin $node:/tmp
      out="$(ssh $node "/tmp/bin/check_node.sh ${BRKMNTS[$i]}")"
      err=$?
      if (( err != 0 )) ; then
	echo "ERROR on $node: $out"
	exit 1
      fi
  done

  echo "All nodes passed check for hadoop workloads"
}

# mk_volmnt: create gluster-fuse mount, per node, using the correct mount
# options. The volume mount is the VOLMNT prefix with VOLNAME appended. The
# mount is persisted in /etc/fstab. Exits on errors.
# Assumptions: the bin scripts have been copied to each node in /tmp/bin.
# Uses globals:
#   NODES
#   VOLNAME
#   VOLMNT
function mk_volmnt() {

  local err; local out; local i; local node
  local volmnt="$VOLMNT/$VOLNAME"
  local \
    mntopts='entry-timeout=0,attribute-timeout=0,use-readdirp=no,acl,_netdev'

  for node in ${NODES[@]}; do
      out="$(ssh $node "
	mkdir -p $volmnt
	# append mount to fstab, if not present
	if ! grep -qs $volmnt /etc/fstab ; then
	  echo '$node:/$VOLNAME $volmnt glusterfs $mntopts 0 0' >>/etc/fstab
	fi
	mount $volmnt # mount via fstab
	rc=\$?
	if (( rc != 0 && rc != 32 )) ; then # 32=already mounted
	  echo Error \$rc: mounting $volmnt with $mntopts options
	  exit 1
	fi
      ")"
      if (( $? != 0 )) ; then
	echo "ERROR on $node: $out"
	exit 1
      fi
  done
}

# add_distributed_dirs: create, if needed, the distributed hadoop directories.
# Note: the gluster-fuse mount, by convention is the VOLMNT prefix with the
#   volume name appended.
# Uses globals:
#   VOLNAME
#   VOLMNT
#   PREFIX
function add_distributed_dirs() {

  local err

  # add the required distributed hadoop dirs
  $PREFIX/bin/add_dirs.sh -d "$VOLMNT/$VOLNAME"
  err=$?
  if (( err != 0 )) ; then
    echo "ERROR $err: add_dirs -d $VOLMNT/$VOLNAME"
  fi
}

# create_vol: gluster vol create VOLNAME with a hard-codes replica 2 and set
# its performance settings. Exits on errors.
# Uses globals:
#   NODES
#   BRKMNTS
#   VOLNAME
function create_vol() {

  local bricks=''; local err; local i; local out

  # create the gluster volume, replica 2 is hard-coded for now
  for (( i=0; i<${#NODES[@]}; i++ )); do
      bricks+="${NODES[$i]}:${BRKMNTS[$i]}/$VOLNAME "
  done

  out="$(gluster volume create $VOLNAME replica 2 $bricks 2>&1)"
  err=$?
  if (( err != 0 )) ; then
    echo "ERROR $err: gluster vol create $VOLNAME $bricks: $out"
    exit 1
  fi
  echo "\"$VOLNAME\" created"

  # set vol performance settings
  $PREFIX/bin/set_vol_perf.sh $VOLNAME
}

# start_vol: gluster vol start VOLNAME. Exits on errors.
# Uses globals:
#   VOLNAME
function start_vol() {

  local err; local out

  out="$(gluster --mode=script volume start $VOLNAME 2>&1)"
  err=$?
  if (( err != 0 )) ; then # serious error or vol already started
    if grep -qs ' already started' <<<$out ; then
      echo "\"$VOLNAME\" volume already started..."
    else
      echo "ERROR $err: gluster vol start $VOLNAME: $out"
      exit 1
    fi
  else
    echo "\"$VOLNAME\" volume started"
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
exit ###!!!!!!!!!!!

# verify that each node is prepped for hadoop workloads
chk_nodes

# create and start the replica 2 volume and set perf settings
create_vol
start_vol

# create gluster-fuse mount, per node
mk_volmnt

# add the distributed hadoop dirs
add_distributed_dirs

exit 0
