#!/bin/bash
#
# create_vol.sh accepts a volume name, volume mount path prefix, and a list of
# two or more "node:brick_mnt" pairs and creates a new volume. Each node spanned
# by the new volume is checked that it is setup for hadoop workloads, and that
# hadoop volume performance settings are set. The volume is mounted with the
# correct glusterfs-fuse mount options.
#
# Syntax (all positional):
#  $1=volName: name of the new volume
#
#  $2=vol-mnt-prefix: path of the glusterfs-fuse mount point, eg. /mnt/glusterfs.
#     Note: the volume name will be appended to this mount point.
#
#  $3=node-list: a list of (minimally) 2 nodes and 1 brick mount path. For
#     example: "create_vol.sh HadoopVol /mnt/glusterfs rhs21-1:/mnt/brick1 
#                rhs21-2"
#     the glusterfs-fuse mount on node rhs21-1 will be "/mnt/glusterfs/HadoopVol"
#     The general syntax is: <node1>:<brkmnt1> <node1>[:<brkmnt2>] ... 
#       <nodeN>[:<brkmntN>]
#     The first <brkmnt> is required. If all the nodes use the same path to
#     their brick mounts then there is no need to repeat the brick mount point.
#     If a node uses a different brick mount then it is defined following a
#     ":" after the node name.
#
# Assumption: script must be executed from a node that has access to the 
#  gluster cli.

## funtions ##

# parse_cmd: simple positional parsing. Exits on errors.
# Sets globals:
#   VOLNAME
#   VOLMNT
#   NODE_SPEC (node:brkmnt)
function parse_cmd() {

  local errcnt=0

  VOLNAME="$1"; shift
  VOLMNT="$1"; shift
  NODE_SPEC=($@) # array of nodes:brick-mnts.

  # check required args
  [[ -z "$VOLNAME" ]] && {
    echo "Syntax error: volume name is required";
    ((errcnt++)); }
  [[ -z "$VOLMNT" ]] && {
    echo "Syntax error: volume mount path prefix is required";
    ((errcnt++)); }
  [[ -z "$NODE_SPEC" || ${#NODE_SPEC[@]} < 2 ]] && {
    echo "Syntax error: expect list of 2 or more nodes plus brick mount(s)";
    ((errcnt++)); }

  (( errcnt > 0 )) && exit 1
}

# parse_nodes: set the global NODES array from NODE_SPEC.
# Uses globals:
#   NODE_SPEC
# Sets globals:
#   NODES
function parse_nodes() {

  local node_spec

  # parse out list of nodes, format: "node:brick-mnt"
  for node_spec in ${NODE_SPEC[@]}; do
      NODES+=(${node_spec%%:*})
  done
}

# parse_brkmnts: extracts the brick mounts from the global NODE_SPEC array.
# Fills in default brkmnts based on the values included on the first node
# (required). Exits on syntax errors.
# Uses globals:
#   NODE_SPEC
# Sets globals:
#   BRKMNTS
function parse_brkmnts() {

  local brkmnt; local brkmnts
  local node_spec; local i

  # extract the required brick-mnt from the 1st node-spec entry
  brkmnt=${NODE_SPEC[0]#*:}

  if [[ -z "$brkmnt" ]] ; then
    echo "Syntax error: expect a brick mount, preceded by a \":\", to immediately follow the first node"
    exit -1
  fi

  BRKMNTS+=($brkmnt) # set global

  # fill in missing brk-mnts
  for (( i=1; i<${#NODE_SPEC[@]}; i++ )); do # starting at 2nd entry
      node_spec=${NODE_SPEC[$i]}
      case "$(grep -o ':' <<<"$node_spec" | wc -l)" in # num of ":"s
	  0) # brkmnt omitted
	     BRKMNTS+=($brkmnt) # default
          ;;
	  1) # brkmnt specified
	     BRKMNTS+=(${node_spec#*:})
          ;;
          *) 
	     echo "Syntax error: improperly specified node-list"
	     exit -1
	  ;;
      esac
  done
}

# chk_vol: invokes gluster vol info to see if VOLNAME already exists. Exits
# on errors.
# Uses globals:
#   VOLNAME
function chk_vol() {

  local err

  gluster volume info $VOLNAME >& /dev/null
  err=$?
  if (( err == 0 )) ; then
    echo "ERROR: volume \"$VOLNAME\" already exists"
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

BRKMNTS=(); NODES=()
PREFIX="$(dirname $(readlink -f $0))"
errcnt=0

parse_cmd $@

parse_nodes

parse_brkmnts

echo
echo "****NODES=${NODES[@]}"
echo "****BRKMNTS=${BRKMNTS[@]}"
echo

# make sure the volume doesn't already exist
chk_vol

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
