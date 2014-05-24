#!/bin/bash
#
# TODO:
# 1) verification
#
# create_vol.sh accepts a volume name, volume mount path prefix, and a list of
# two or more "node:brick_mnt" pairs, and creates a new volume with the
# appropriate performance settings set. Each node spanned by the new volume is
# checked to make sure it is setup for hadoop workloads. The new volume is
# startedxi and the volume is mounted with the correct glusterfs-fuse mount
# options. Lastly, distributed, hadoop-specific directories are created.
# Note: nodes that are not spanned by the new volume are not modified in any
#   way. See enable_vol.sh, which establishes a nfs mount on the yarn-master
#   node and handles core-site file changes.
#
# See useage() for syntax.

PREFIX="$(dirname $(readlink -f $0))"

## functions ##

source $PREFIX/bin/functions

# usage: output the description and syntax.
function usage() {

  cat <<EOF

$ME creates and prepares a new volume designated for hadoop workloads. The 
replica factor is hard-coded to 2, per RHS requirements.

SYNTAX:

$ME --version | --help

$ME [-y] <volname> <volume-mnt-prefix> <node-list-spec>

where:

  <node-spec-list> : a list of two or more <node-spec>s.
  <node-spec> : a storage node followed by a ':', followed by a brick mount
      path.  Eg:
         <node1><:brickmnt1>  <node2>[:<brickmnt2>] ...
      Each node is expected to be separate from the management and yarn-master
      nodes. Only the brick mount path associated with the first node is
      required. If omitted from the other <node-spec-list> members then each node
      assumes the value of the first node for the brick mount path.

  <volname> : name of the new volume.
  <vol-mnt-prefix> : path of the glusterfs-fuse mount point, eg. /mnt/glusterfs.
      Note: the volume name will be appended to this mount point.
  -y : auto answer "yes" to all prompts. Default is to be promoted before the
      script continues.
  --version : output only the version string.
  --help : this text.

EOF
}

# parse_cmd: simple positional parsing. Returns 1 on errors.
# Sets globals:
#   VOLNAME
#   VOLMNT
#   NODE_SPEC (node:brkmnt)
function parse_cmd() {

  local errcnt=0
  local long_opts='help,version'

  eval set -- "$(getopt -o 'y' --long $long_opts -- $@)"

  while true; do
      case "$1" in
        -y)
          AUTO_YES=1; shift; continue
        ;;
        --help)
          usage; exit 0
        ;;
        --version) # version is already output, so nothing to do here
          exit 0
        ;;
        --)
          shift; break
        ;;
      esac
  done

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

  (( errcnt > 0 )) && return 1
  return 0
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
# (required). Returns 1 on syntax errors.
# Uses globals:
#   NODE_SPEC
# Sets globals:
#   BRKMNTS
function parse_brkmnts() {

  local brkmnts
  local node_spec; local i
  # extract the required brick-mnt from the 1st node-spec entry
  local brkmnt=${NODE_SPEC[0]#*:}

  if [[ -z "$brkmnt" ]] ; then
    echo "Syntax error: expect a brick mount, preceded by a \":\", to immediately follow the first node"
    return 1
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
	     return 1
	  ;;
      esac
  done

  return 0
}

# chk_nodes: verify that each node that will be spanned by the new volume is 
# prepped for hadoop workloads by invoking bin/check_node.sh. Returns 1 on 
# errors.
# Uses globals:
#   BRKMNTS
#   NODES
#   PREFIX
# Side effect: all scripts under bin/ are copied to each node.
function chk_nodes() {

  local i=0; local node; local err; local out
  local ssh; local scp

  # verify that each node is prepped for hadoop workloads
  for node in ${NODES[@]}; do
      [[ "$node" == "$HOSTNAME" ]] && { ssh=''; scp='#'; } || \
				       { ssh="ssh $node"; scp='scp'; }
      eval "$scp -r -q $PREFIX/bin $node:/tmp"
      out="$(eval "
	$ssh /tmp/bin/check_node.sh ${BRKMNTS[$i]}
      ")"
      err=$?
      if (( err != 0 )) ; then
	echo "ERROR on $node: $out"
	return 1
      fi
      ((i++))
  done

  echo "All nodes passed check for hadoop workloads"
  return 0
}

# mk_volmnt: create gluster-fuse mount, per node, using the correct mount
# options. The volume mount is the VOLMNT prefix with VOLNAME appended. The
# mount is persisted in /etc/fstab. Returns 1 on errors.
# Assumptions: the bin scripts have been copied to each node in /tmp/bin.
# Uses globals:
#   NODES
#   PREFIX
#   VOLMNT
#   VOLNAME
function mk_volmnt() {

  local err; local out; local node; local ssh; local ssh_close
  local volmnt="$VOLMNT/$VOLNAME"

  # assign required and optional gluster-fuse mount options
  local mntopts="$($PREFIX/bin/gen_req_gluster_mnt.sh),"
  mntopts+="$($PREFIX/bin/gen_opt_gluster_mnt.sh),_netdev" # add _netdev here

  for node in ${NODES[@]}; do
      [[ "$node" == "$HOSTNAME" ]] && { ssh='('; ssh_close=')'; } \
			            || { ssh="ssh $node '"; ssh_close="'"; }
      out="$(eval "
	$ssh
	  mkdir -p $volmnt
	  # append mount to fstab, if not present
	  if ! grep -qs $volmnt /etc/fstab ; then
	    echo $node:/$VOLNAME $volmnt glusterfs $mntopts 0 0 >>/etc/fstab
	  fi
	  mount $volmnt # mount via fstab
	  rc=\$?
	  if (( rc != 0 && rc != 32 )) ; then # 32=already mounted
	    echo Error \$rc: mounting $volmnt with $mntopts options
	    exit 1 # from ssh or sub-shell
	  fi
	  exit 0 # from ssh or sub-shell
	$ssh_close
      ")"
      if (( $? != 0 )) ; then
	echo "ERROR on $node: $out"
	return 1
      fi
  done

  return 0
}

# add_distributed_dirs: create, if needed, the distributed hadoop directories.
# Returns 1 on errors.
# Note: the gluster-fuse mount, by convention is the VOLMNT prefix with the
#   volume name appended.
# DEPENDENCY:
#   1) all bin/* scripts have been copied to /tmp/bin on the FIRST_NODE.
#      Currently this has been done by chk_nodes().
# Uses globals:
#   FIRST_NODE
#   VOLNAME
#   VOLMNT
function add_distributed_dirs() {

  local err; local ssh

  # add the required distributed hadoop dirs
  [[ "$FIRST_NODE" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $FIRST_NODE"
  eval "$ssh /tmp/bin/add_dirs.sh -d $VOLMNT/$VOLNAME"
  err=$?
  if (( err != 0 )) ; then
    echo "ERROR $err: add_dirs -d $VOLMNT/$VOLNAME"
    return 1
  fi

  return 0
}

# create_vol: gluster vol create VOLNAME with a hard-codes replica 2 and set
# its performance settings. Returns 1 on errors.
# Uses globals:
#   FIRST_NODE
#   NODES
#   BRKMNTS
#   VOLNAME
function create_vol() {

  local bricks=''; local err; local i; local out

  # create the gluster volume, replica 2 is hard-coded for now
  for (( i=0; i<${#NODES[@]}; i++ )); do
      bricks+="${NODES[$i]}:${BRKMNTS[$i]}/$VOLNAME "
  done

  out="$(ssh $FIRST_NODE "gluster volume create $VOLNAME replica 2 $bricks 2>&1"
       )"
  err=$?
  if (( err != 0 )) ; then
    echo "ERROR $err: gluster vol create $VOLNAME $bricks: $out"
    return 1
  fi
  echo "\"$VOLNAME\" created"

  # set vol performance settings
  if ! $PREFIX/bin/set_vol_perf.sh -n $FIRST_NODE $VOLNAME ; then
    return 1
  fi
  return 0
}

# start_vol: gluster vol start VOLNAME. Returns 1 on errors.
# Uses globals:
#   FIRST_NODE
#   VOLNAME
function start_vol() {

  local err; local out

  out="$(ssh $FIRST_NODE "gluster --mode=script volume start $VOLNAME 2>&1"
       )"
  err=$?
  if (( err != 0 )) ; then # serious error or vol already started
    if grep -qs ' already started' <<<$out ; then
      echo "WARN: \"$VOLNAME\" volume already started..."
    else
      echo "ERROR $err: gluster vol start $VOLNAME: $out"
      return 1
    fi
  else
    echo "\"$VOLNAME\" started"
  fi

  return 0
}


## main ##

ME="$(basename $0 .sh)"
AUTO_YES=0 # assume false
BRKMNTS=(); NODES=()
errcnt=0

echo '***'
echo "*** $ME: version $(cat $PREFIX/VERSION)"
echo '***'

parse_cmd $@ || exit -1

parse_nodes
FIRST_NODE=${NODES[0]} # use this storage node for all gluster cli cmds

# check for passwordless ssh connectivity to nodes
check_ssh ${NODES[@]} || exit 1

# make sure the volume doesn't already exist
vol_exists $VOLNAME $FIRST_NODE && {
  echo "ERROR: volume \"$VOLNAME\" already exists";
  exit 1; }

parse_brkmnts || exit 1

echo
echo "*** Nodes       : ${NODES[@]}"
echo "*** Brick mounts: ${BRKMNTS[@]}"
echo

# verify that each node is prepped for hadoop workloads
chk_nodes  || exit 1

# prompt to continue before any changes are made...
echo
(( ! AUTO_YES )) && ! yesno "Creating new volume $VOLNAME. Continue? [y|N] " && \
  exit 0

# create and start the replica 2 volume and set perf settings
create_vol || exit 1
start_vol  || exit 1

# create gluster-fuse mount, per node
mk_volmnt  || exit 1

# add the distributed hadoop dirs
add_distributed_dirs || exit 1

exit 0
