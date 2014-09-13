#!/bin/bash
#
# create_vol.sh accepts a volume name, volume mount path prefix, and a list of
# two or more "node:brick_mnt" pairs, and creates a new volume, spanning the
# supplied nodes, with the appropriate performance settings set. Each node
# spanned by the new volume is checked to make sure it is setup for hadoop
# workloads. The new volume is started and the volume is mounted with the
# correct glusterfs-fuse mount options. Lastly, the distributed hadoop-specific
# directories are created.
# Note: nodes that are not spanned by the new volume will still have the volume
#   mounted so that hadoop jobs running on these nodes have access to the data.
#
# See useage() for syntax.

PREFIX="$(dirname $(readlink -f $0))"

## functions ##

source $PREFIX/bin/functions

# usage: output the description and syntax.
function usage() {

  cat <<EOF

$ME creates and prepares a new volume designated for hadoop workloads.
The replica factor is hard-coded to 2, per RHS requirements.

SYNTAX:

$ME --version | --help

$ME [-y] [--quiet | --verbose | --debug] \\
           <volname> <vol-mnt-prefix> <nodes-spec-list>

where:

<nodes-spec-list>: a list of two or more <node-spec's>.
<node-spec>     : a storage node followed by a ':', followed by a brick mount
                  path.  Eg:
                     <node1><:brickmnt1>  <node2>[:<brickmnt2>] ...
                  A volume does not need to span all nodes in the cluster. Only
                  the brick mount path associated with the first node is
                  required. If omitted from the other <nodes-spec-list> members
                  then each node assumes the value of the first node for the
                  brick mount path.
<volname>       : name of the new volume.
<vol-mnt-prefix>: path of the glusterfs-fuse mount point, eg. /mnt/glusterfs.
                  Note: the volume name will be appended to this mount point.
-y              : auto answer "yes" to all prompts. Default is to be promoted 
                  before the script continues.
--quiet         : (optional) output only basic progress/step messages. Default.
--verbose       : (optional) output --quiet plus more details of each step.
--debug         : (optional) output --verbose plus greater details useful for
                  debugging.
--version       : output only the version string.
--help          : this text.

EOF
}

# parse_cmd: simple positional parsing. Returns 1 on errors.
# Sets globals:
#   VOLNAME
#   VOLMNT
#   NODE_SPEC (node:brkmnt)
function parse_cmd() {

  local errcnt=0
  local long_opts='help,version,quiet,verbose,debug'

  eval set -- "$(getopt -o 'y' --long $long_opts -- $@)"

  while true; do
      case "$1" in
        --help)
          usage; exit 0
        ;;
        --version) # version is already output, so nothing to do here
          exit 0
        ;;
        --quiet)
          VERBOSE=$LOG_QUIET; shift; continue
        ;;
        --verbose)
          VERBOSE=$LOG_VERBOSE; shift; continue
        ;;
        --debug)
          VERBOSE=$LOG_DEBUG; shift; continue
        ;;
        -y)
          AUTO_YES=1; shift; continue
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
  if [[ -z "$NODE_SPEC" ]] || (( ${#NODE_SPEC[@]} < 2 )) ; then
    echo "Syntax error: expect list of 2 or more nodes plus brick mount(s)"
    ((errcnt++))
  fi

  (( errcnt > 0 )) && return 1
  return 0
}

# parse_nodes_brkmnts: extracts the nodes and brick mounts from the global
# NODE_SPEC array. Fills in default brkmnts based on the values included for
# the first node (required). Returns 1 on syntax errors.
# Uses globals:
#   NODE_SPEC
#   REPLICA_CNT
# Sets globals:
#   BRKMNTS (assoc array)
#   VOL_NODES()
function parse_nodes_brkmnts() {

  local node_spec=(${NODE_SPEC[0]//:/ }) # split after subst ":" with space
  local def_brkmnt=${node_spec[1]} # default
  local node; local all_mnts=()

  if [[ -z "$def_brkmnt" ]] ; then
    echo "Syntax error: expect a brick mount, preceded by a \":\", to immediately follow the first node"
    return 1
  fi

  # fill in missing brk-mnts
  for node_spec in ${NODE_SPEC[@]}; do
      node=${node_spec%:*}
      case "$(grep -o ':' <<<"$node_spec" | wc -l)" in # num of ":"s
	  0) # brkmnt omitted
	     BRKMNTS[$node]+="$def_brkmnt "
          ;;
	  1) # brkmnt specified
	     BRKMNTS[$node]+="${node_spec#*:} "
          ;;
          *) 
	     echo "Syntax error: improperly specified nodes-spec-list"
	     return 1
	  ;;
      esac
  done

  # verify that the number of bricks is a multiple of the replica count
  all_mnts=(${BRKMNTS[@]})
  if (( ${#all_mnts[@]} % REPLICA_CNT != 0 )) ; then
    err "the number of bricks must be a multiple of the replica, which is $REPLICA_CNT"
    return 1
  fi

  # assign unique volume nodes
  VOL_NODES=($(printf '%s\n' "${!BRKMNTS[@]}" | sort))

  return 0
}

# set_non_vol_nodes: find all nodes in the storage pool that are not spanned by
# the new volume. Returns 1 on errors.
# Uses globals:
#   FIRST_NODE
#   VOL_NODES
# Sets globals:
#   EXTRA_NODES
function set_non_vol_nodes() {

  local node; local pool; local err
  EXTRA_NODES=() # set global var, can be empty

  pool=($($PREFIX/bin/find_nodes.sh -n $FIRST_NODE -u)) # uniq nodes in pool
  err=$?
  (( err != 0 )) && {
    err $err "cannot find storage pool nodes: ${pool[*]}";
    return 1; }

  debug "all nodes in storage pool: ${pool[*]}"

  # find nodes in pool that are not spanned by volume
  for node in ${pool[@]}; do
      [[ "${VOL_NODES[*]}" =~ $node ]] && continue
      EXTRA_NODES+=($node)
  done

  debug "nodes *not* spanned by new volume: ${EXTRA_NODES[*]}"
  return 0
}

# path_avail: return 0 (true) if the full path is available on *all* nodes (eg.
# does not exist on any node). Return false (1) if the full path is not
# available on *all* nodes (eg. false if it exists on any node).
# Uses globals:
#   BRKMNTS()
#   VOL_NODES()
#   VOLNAME
function path_avail() {

  local node; local cnt=0; local out

  for node in ${VOL_NODES[@]}; do
      out="$(ssh $node "
	for mnt in ${BRKMNTS[$node]}; do # typically a single mnt
	    [[ -e \$mnt/$VOLNAME ]] && {
	      echo \"mount path exists for \$mnt/$VOLNAME on $node\";
	      exit 1; }
	done
	exit 0
	")"
      (( $? == 1 )) && { # mnt path exists on node
	err "$out"; break; }
      ((cnt++))
  done

  (( cnt < ${#VOL_NODES[@]} )) && return 1 # mnt path exists somewhere...
  debug "No nodes contain $VOLNAME as an existing mount path"
  return 0
}

# chk_nodes: verify that each node that will be spanned by the new volume is 
# prepped for hadoop workloads by invoking bin/check_node.sh. Also, verify that
# the hadoop GID and user UIDs are consistent across the nodes. Returns 1 on
# errors.
# Uses globals:
#   BRKMNTS()
#   EXTRA_NODES
#   LOGFILE
#   PREFIX
#   VOL_NODES
#   VOLNAME
function chk_nodes() {

  local node; local err; local errcnt=0; local out; local ssh

  verify_gid_uids ${VOL_NODES[*]} ${EXTRA_NODES[*]}
  (( $? != 0 )) && ((errcnt++))

  verbose "--- checking all nodes spanned by $VOLNAME..."

  # verify that each node is prepped for hadoop workloads
  for node in ${VOL_NODES[@]}; do
      [[ "$node" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $node"

      out="$(eval "$ssh $PREFIX/bin/check_node.sh ${BRKMNTS[$node]}")"
      err=$?
      if (( err != 0 )) ; then
	err -e $err "check_node on $node:\n$out"
	((errcnt++))
      else
	debug -e "check_node on $node:\n$out"
      fi
  done

  (( errcnt > 0 )) && return 1
  verbose "all nodes passed check for hadoop workloads"
  return 0
}

# mk_volmnt: create gluster-fuse mount, per node, using the correct mount
# options, permissions and owner. The volume mount is the VOLMNT prefix with
# VOLNAME appended. The mount is persisted in /etc/fstab. Returns 1 on errors.
# Assumptions:
#   1) the required hadoop group and hadoop users have been created.
# Uses globals:
#   EXTRA_NODES (can be empty)
#   PREFIX
#   VOL_NODES
#   VOLMNT
#   VOLNAME
function mk_volmnt() {

  local err; local errcnt=0; local out; local node
  local volmnt="$VOLMNT/$VOLNAME"

  verbose "--- creating glusterfs-fuse mounts for $VOLNAME..."

  for node in ${VOL_NODES[*]} ${EXTRA_NODES[*]}; do
      out="$(ssh $node "
	  source $PREFIX/bin/functions
          gluster_mnt_vol $node $VOLNAME $volmnt
      ")"
      err=$?
      if (( err != 0 )) ; then
	((errcnt++))
	err $err "glusterfs mount on $node: $out"
      else
	debug "glusterfs mount on $node: $out"
      fi
  done

  (( errcnt > 0 )) && return 1
  verbose "--- created glusterfs-fuse mounts for $VOLNAME"
  return 0
}

# add_distributed_dirs: create the distributed hadoop directories. Returns 1 on
# errors.
# Note: the gluster-fuse mount, by convention, is the VOLMNT prefix with the
#   volume name appended.
# Uses globals:
#   FIRST_NODE
#   PREFIX
#   VOLMNT
#   VOLNAME
function add_distributed_dirs() {

  local err; local ssh; local out

  verbose "--- adding hadoop directories to nodes spanned by $VOLNAME..."

  [[ "$FIRST_NODE" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $FIRST_NODE"

  # add the required distributed hadoop dirs
  out="$(eval "$ssh $PREFIX/bin/add_dirs.sh -d $VOLMNT/$VOLNAME")"
  err=$?
  if (( err != 0 )) ; then
    err $err "could not add required hadoop dirs: $out"
    return 1
  fi
  debug -e "add_dirs -d $VOLMNT/$VOLNAME:\n$out"

  verbose "--- added hadoop directories to nodes spanned by $VOLNAME"
  return 0
}

# create_vol: gluster vol create VOLNAME with a hard-coded replica 2 and set
# its performance settings. Returns 1 on errors.
# Uses globals:
#   BRKMNTS()
#   FIRST_NODE
#   REPLICA_CNT
#   VOLNAME
#   VOL_NODES
function create_vol() {

  local bricks=''; local err; local out; local node; local i 
  local mnt; local mnts_per_node
  local mnts=(${BRKMNTS[@]}) # array of all mnts across all nodes
  let mnts_per_node=(${#mnts[@]} / ${#VOL_NODES[@]})

  verbose "--- creating the new $VOLNAME volume..."

  # define the brick list -- order matters for replica!
  # note: round-robin the mnts so that the original command nodes-spec list
  #   order is preserved
  for (( i=0; i<mnts_per_node; i++ )) ; do # typically 1 mnt per node
      for node in ${VOL_NODES[@]}; do
	  mnts=(${BRKMNTS[$node]}) # array, typically 1 mnt entry
	  mnt=${mnts[$i]}
	  bricks+="$node:$mnt/$VOLNAME "
      done
  done
  debug "bricks: $bricks"

  # create the gluster volume, replica 2 is hard-coded for now
  out="$(ssh $FIRST_NODE "
	    gluster volume create $VOLNAME replica $REPLICA_CNT $bricks 2>&1")"
  err=$?
  if (( err != 0 )) ; then
    err $err "gluster vol create $VOLNAME $bricks: $out"
    return 1
  fi
  debug "gluster vol create: $out"
  verbose "--- \"$VOLNAME\" created"

  verbose "--- setting performance options on $VOLNAME..."
  out="$($PREFIX/bin/set_vol_perf.sh -n $FIRST_NODE $VOLNAME)"
  err=$?
  if (( err != 0 )) ; then
    err $err "set_vol_perf: $out"
    return 1
  fi
  debug "set_vol_perf: $out"

  verbose "--- performance options set"
  return 0
}

# start_vol: gluster vol start VOLNAME. Returns 1 on errors.
# Uses globals:
#   FIRST_NODE
#   VOLNAME
function start_vol() {

  local err; local out

  verbose "--- starting the new $VOLNAME volume..."

  out="$(ssh $FIRST_NODE "gluster --mode=script volume start $VOLNAME 2>&1"
       )"
  err=$?
  if (( err != 0 )) ; then # either serious error or vol already started
    if grep -qs ' already started' <<<$out ; then
      warn "\"$VOLNAME\" volume already started..."
    else
      err $err "gluster vol start $VOLNAME: $out"
      return 1
    fi
  fi
  debug "gluster vol start: $out"

  verbose "\"$VOLNAME\" started"
  return 0
}


## main ##

ME="$(basename $0 .sh)"
AUTO_YES=0 # assume false
VOL_NODES=()
declare -A BRKMNTS=() # assco array, node=key list of 1 or more mnt=value
REPLICA_CNT=2  # hard-coded for now
VERBOSE=$LOG_QUIET # default
errcnt=0

report_version $ME $PREFIX

parse_cmd $@ || exit -1

parse_nodes_brkmnts || exit -1
FIRST_NODE=${VOL_NODES[0]} # use this storage node for all gluster cli cmds

# make sure the volume doesn't already exist
vol_exists $VOLNAME $FIRST_NODE && {
  err "volume \"$VOLNAME\" already exists";
  exit 1; }

# check for passwordless ssh connectivity to storage nodes
check_ssh ${VOL_NODES[*]} || exit 1

# volume name can't conflict with other names under the brick mnts
path_avail || exit 1

# find the nodes in the pool but not spanned by the new volume
set_non_vol_nodes || exit 1 # sets EXTRA_NODES array (can be empty)

# check for passwordless ssh connectivity to extra nodes
check_ssh ${EXTRA_NODES[*]} || exit 1

echo
quiet "*** Volume        : $VOLNAME"
quiet "*** Nodes         : $(echo ${VOL_NODES[*]} | sed 's/ /, /g')"
[[ -n "$EXTRA_NODES" ]] && {
  quiet "*** Nodes not spanned by vol: $(echo ${EXTRA_NODES[*]} | \
	sed 's/ /, /g')"; }
quiet "*** Volume mount  : $VOLMNT"
quiet "*** Brick mounts"
for node in ${VOL_NODES[@]}; do
    let fill=(11-${#node}) # to left-justify node
    fmt_node="$node $(printf ' %.0s' $(seq $fill))"
    quiet "      $fmt_node: ${BRKMNTS[$node]}"
done
echo

# verify that each node is prepped for hadoop workloads
chk_nodes || exit 1

# prompt to continue before any changes are made...
(( ! AUTO_YES )) && \
  ! yesno "Creating new volume $VOLNAME. Continue? [y|N] " && exit 0

# create and start the replica 2 volume and set perf settings
create_vol || exit 1
start_vol || exit 1

# create gluster-fuse mount, per node
mk_volmnt || exit 1

# add the distributed hadoop dirs
add_distributed_dirs || exit 1

quiet "\"$VOLNAME\" created and started with no errors"
exit 0
