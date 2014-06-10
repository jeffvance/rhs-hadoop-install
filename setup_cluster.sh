#!/bin/bash
#
# TODO:
# 1) CDN register each node, including yarn and mgmt nodes
# 2) verify brick xfs mount options, eg noatime
# 3) wait for nodes to join trusted pool
# 4) remove useradd/groupadd code and use ipa scripts
# 5) --ldap[=extra-users], --no-users (default)
#
# setup_cluster.sh accepts a list of nodes:brick-mnts:block-devs, along with
# the name of the yarn-master and hadoop-mgmt servers, and creates a new trusted
# pool with each node in the node-list setup as a storage/data node. If the pool
# already exists then the supplied nodes are setup anyway as a verification step.
# The yarn and mgmt nodes are expected to be outside of the pool, and not to be
# the same server; however these recommendations are not enforced by the script.
#
# Before any steps can be performed the user-created repo file is copied to all
# nodes provided (including the yarn-master and management nodes), and a yum
# install is done to install the rhs-hadoop plugin and the rhs-hadoop-install
# installer. That is how this script become available.
#
# On each node the blk-device is setup as an xfs file system and mounted to the
# brick mount dir, ntp config is verified, required gluster & ambari ports are
# checked to be open, selinux is set to permissive, hadoop required users are
# created, and the required hadoop local directories are created (note: the
# required distributed dirs are not created here).
#
# Also, on all nodes (assumed to be storage- data-nodes) and on the yarn-master
# server node, the ambari agent is installed (updated if present) and started.
# If the hadoop management node is outside of the storage pool then it will not
# have the agent installed. Last, the ambari-server is installed and started on
# the mgmt-node.
#
# Tasks related to volumes and/or ambari setup are not done here.
#
# See usage() for syntax.

PREFIX="$(dirname $(readlink -f $0))"

## functions ##

source $PREFIX/bin/functions

# usage: output the description and syntax.
function usage() {

  cat <<EOF

$ME sets up a storage cluster for hadoop workloads.

SYNTAX:

$ME --version | --help

$ME [-y] [--hadoop-management-node <node>] [--yarn-master <node>] \\
              [--quiet | --verbose | --debug] \\
              <nodes-spec-list>
where:

<node-spec-list>: a list of two or more <node-spec>s.
<node-spec>     : a storage node followed by a ':', followed by a brick mount
                  path, followed by another ':', followed by a block device path.
                  Eg: <node1><:brickmnt1>:<blkdev1> <node2>[:<brickmnt2>]
                      [:<blkdev2>] [<node3>] ...
                  Each node is expected to be separate from the management and 
                  yarn-master nodes. Only the brick mount path and the block
                  device path associated with the first node are required. If
                  omitted from the other <node-spec-list> members then each node
                  assumes the values of the first node for brick mount path and
                  block device path. If a brick mount path is omitted but a
                  block device path is specified then the block device path is
                  proceded by two ':'s, eg. "<nodeN>::<blkdevN>"
--yarn-master   : (optional) hostname or ip of the yarn-master server which is
                  expected to be outside of the storage pool. Default is
                  localhost.
--hadoop-mgmt-node: (optional) hostname or ip of the hadoop mgmt server which
                  is expected to be outside of the storage pool. Default is
                  localhost.
-y              : (optional) auto answer "yes" to all prompts. Default is to 
                  answer a confirmation prompt.
--quiet         : (optional) output only basic progress/step messages. Default.
--verbose       : (optional) output --quiet plus more details of each step.
--debug         : (optional) output --verbose plus greater details useful for
                  debugging.
--version       : output only the version string.
--help          : this text.

EOF
}

# parse_cmd: use get_opt to parse the command line. Returns 1 on errors.
# Sets globals:
#   AUTO_YES
#   MGMT_NODE
#   NODE_SPEC
#   VERBOSE
#   YARN_NODE
function parse_cmd() {

  local opts='y'
  local long_opts='help,version,yarn-master:,hadoop-mgmt-node:,verbose,quiet,debug'
  local errcnt=0

  eval set -- "$(getopt -o $opts --long $long_opts -- $@)"

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

  # check required args
  NODE_SPEC=($@) # array of nodes, brick-mnts, blk-devs -- each separated by ":"
  [[ -z "$NODE_SPEC" || ${#NODE_SPEC[@]} < 2 ]] && {
    echo "Syntax error: expect list of 2 or more nodes plus brick mount(s) and block dev(s)";
    ((errcnt++)); }

  (( errcnt > 0 )) && return 1
  return 0
}

# parse_nodes_brkmnts_blkdevs: set the global NODE_BRKMNTS and NODE_BLKDEVS 
# arrays based on NODE_SPEC. The format of these assoc arrays is:
#   NODE_BRKMNTS[<node>]="<brickmnt>[,<brkmnt1>][,<brmknt2>]..."
#   NODE_BLKDEVS[<node>]="<blkdev>[,<blkdev>][,<blkdev>]..."
# The brick mount and block dev values are a comma separated list. Most times
# the list contains only one brick-mnt/block-dev, but to handle the case of the
# same node repeated with different brick-mnt and/or block-dev paths we use a 
# list. 
# A check is made to see if the management node and/or yarn-master node is inside
# the storage pool and/or are the same node, and if so a warning is reported and
# the user is prompted to continue. Returns 1 if user answers no.
# Uses globals:
#   AUTO_YES
#   NODE_SPEC
#   YARN_NODE
#   MGMT_NODE
# Sets globals:
#   MGMT_INSIDE
#   NODES (*unique* storage nodes)
#   NODE_BLKDEVS
#   NODE_BRKMNTS
#   YARN_INSIDE
function parse_nodes_brkmnts_blkdevs() {

  local node_spec=(${NODE_SPEC[0]//:/ }) # split after subst ":" with space
  local def_brkmnt=${node_spec[1]} # default
  local def_blkdev=${node_spec[2]} # default
  local brkmnts=(); local blkdev

  if [[ -z "$def_brkmnt" || -z "$def_blkdev" ]] ; then
    echo "Syntax error: expect a brick mount and block device to immediately follow the first node (each separated by a \":\")"
    return 1
  fi

  # parse out list of nodes, format: "node[:brick-mnt][:blk-dev]"
  for node_spec in ${NODE_SPEC[@]}; do
      node=${node_spec%%:*}
      # fill in missing brk-mnts and/or blk-devs
      case "$(grep -o ':' <<<"$node_spec" | wc -l)" in # num of ":"s
          0) # brkmnt and blkdev omitted
             NODE_BRKMNTS[$node]+="$def_brkmnt,"
             NODE_BLKDEVS[$node]+="$def_blkdev,"
          ;;
          1) # only brkmnt specified
             NODE_BLKDEVS[$node]+="$def_blkdev,"
             NODE_BRKMNTS[$node]+="${node_spec#*:},"
          ;;
          2) # either both brkmnt and blkdev specified, or just blkdev specified
             blkdev="${node_spec##*:}"
             NODE_BLKDEVS[$node]+="${blkdev},"
             brkmnts=(${node_spec//:/ }) # array
             if [[ "${brkmnts[1]}" == "$blkdev" ]] ; then # "::", empty brkmnt
               NODE_BRKMNTS[$node]+="$def_brkmnt,"
             else
               NODE_BRKMNTS[$node]+="${brkmnts[1]},"
             fi
          ;;
          *)
             echo "Syntax error: improperly specified node-list"
             return 1
          ;;
      esac
      # detect if yarn-master or mgmt node are inside storage pool
      [[ "$node" == "$YARN_NODE" ]] && YARN_INSIDE=1 # true
      [[ "$node" == "$MGMT_NODE" ]] && MGMT_INSIDE=1 # true
  done

  # assign unique storage nodes
  NODES=($(printf '%s\n' "${!NODE_BRKMNTS[@]}" | sort))

  # remove last trailing comma from each node's brk/blk value
  for node in ${NODES[@]}; do
      NODE_BRKMNTS[$node]=${NODE_BRKMNTS[$node]%*,}
      NODE_BLKDEVS[$node]=${NODE_BLKDEVS[$node]%*,}
  done

  # warning if mgmt or yarn-master nodes are inside the storage pool
  if (( MGMT_INSIDE || YARN_INSIDE )) ; then
    if (( MGMT_INSIDE && YARN_INSIDE )) ; then
      warn -e "the yarn-master and hadoop management nodes are inside the storage pool\nwhich is sub-optimal."
    elif (( MGMT_INSIDE )) ; then
      warn "the hadoop mgmt node is inside the storage pool which is sub-optimal."
    else
      warn "the yarn-master node is inside the storage pool which is sub-optimal."
    fi
    (( ! AUTO_YES )) && ! yesno  "  Continue? [y|N] " && return 1
  fi

  # warning if yarn-master == mgmt node
  if [[ "$YARN_NODE" == "$MGMT_NODE" ]] ; then
    warn "the yarn-master and hadoop-mgmt-nodes are the same which is sub-optimal."
    (( ! AUTO_YES )) && ! yesno  "  Continue? [y|N] " && return 1
  fi

  return 0
}

# show_todo: show summary of actions to be done.
# Uses globals:
#   BLKDEVS
#   BRKMNTS
#   MGMT_NODE
#   NODES
#   YARN_NODE
function show_todo() {

  local node

  echo
  quiet "*** Nodes             : $(echo ${NODES[*]} | tr ' ' ', ')"
  quiet "*** Brick mounts"
  for node in ${NODES[@]}; do
      quiet "      $node         : $(echo ${NODE_BRKMNTS[$node]} | tr ' ' ', ')"
  done

  quiet "*** Block devices"
  for node in ${NODES[@]}; do
      quiet "      $node         : $(echo ${NODE_BLKDEVS[$node]} | tr ' ' ', ')"
  done

  quiet "*** Ambari mgmt node  : $MGMT_NODE"
  quiet "*** Yarn-master server: $YARN_NODE"
  echo
}

# copy_bin: copies all bin/* files to /tmp/ on the passed-in nodes. Returns 1
# on errors.
# Uses globals:
#   PREFIX
function copy_bin() {

  local node; local err; local errcnt=0; local out; local cmd
  local nodes_seen='' # don't duplicate the copy

  verbose "--- copying bin/ to /tmp on all nodes..."

  for node in $@ ; do
      [[ "$nodes_seen" =~ " $node " ]] && continue # dup node
      nodes_seen+=" $node " # frame with spaces

      [[ "$node" == "$HOSTNAME" ]] && cmd="cp -r $PREFIX/bin /tmp" \
				   || cmd="scp -qr $PREFIX/bin $node:/tmp"
      out="$(eval "$cmd")"
      err=$?
      if (( err != 0 )) ; then
	((errcnt++))
	err -e $err "could not copy bin/* to /tmp on $node:\n$out"
      fi
      debug "copy bin/ to /tmp on $node: $out"
  done

  (( errcnt > 0 )) && return 1
  return 0
}

# install_repo: copies the repo file expected to be on the install-from node
# (localhost) to the passed-in nodes, and yum installs the packages. Returns 1
# for errors.
function install_repo() {

  local nodes="$@"
  local node; local errcnt=0; local err
  local repo_file='/etc/yum.repos.d/rhs-hadoop.repo'

  # nested function copies the repo file to the passed-in node.
  # Returns 1 on errors.
  function cp_repo() {

    local node="$1"; local err

    out="$(scp $repo_file $node:$repo_file)"
    err=$?
    if (( err != 0 )) ; then
      err -e $err "copying $file to $node:\n$out"
      return 1
    fi
    debug -e "copying repo file to $node in $(dirname $repo_file):\n$out"
    return 0
  }

  # nested function installs the package on the passed-in node.
  # Returns 1 on errors.
  function install_repo() {

    local node="$1"; local err

    out="$(ssh $node 'yum install -y --nogpgcheck rhs-hadoop 2>&1')"
    err=$?
    if (( err != 0 )) ; then
      err -e $err "yum installing $file on $node:\n$out"
      return 1
    fi
    debug -e "yum install repo file on $node:\n$out"
    return 0
  }

  ## main ##

  verbose "--- copying $repo_file and installing on all nodes..."

  [[ ! -f "$repo_file" ]] && {
    err "$repo_file is missing. Cannot install rhs-hadoop package on cluster";
    return 1; }

  for node in $nodes; do
      err=0
      if [[ "$node" != "$HOSTNAME" ]] ; then
	cp_repo $node
        err=$?
        (( err != 0 )) && ((errcnt++))
      fi
      if (( err == 0 )) ; then
	install_repo $node || ((errcnt++))
      fi
  done

  (( errcnt > 0 )) && return 1
  return 0
}

# setup_nodes: setup each node for hadoop workloads by invoking bin/
# setup_datanodes.sh, which is also run for the yarn-master node if it is
# outside of the storage pool. Note: if the hadoop mgmt-node is outside of the
# storage pool then it will not have the agent installed. Returns 1 on errors.
# Uses globals:
#   NODES
#   NODE_BLKDEVS
#   NODE_BRKMNTS
#   PREFIX
#   YARN_INSIDE
#   YARN_NODE
function setup_nodes() {

  local errcnt=0; local errnodes=''
  local node; local brkmnt; local blkdev

  # nested function to call setup_datanodes on a passed-in node, blkdev and
  # brick-mnt.
  function do_node() {

    local node="$1"
    local blkdev="$2" # can be blank
    local brkmnt="$3" # can be blank
    local out; local err; local ssh

    [[ "$node" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $node"

    verbose "+++"
    verbose "+++ begin node $node"
    out="$(eval "
	$ssh /tmp/bin/setup_datanode.sh --blkdev $blkdev \
		--brkmnt $brkmnt --hadoop-mgmt-node $MGMT_NODE
 	")"
    err=$?
    if (( err != 0 )) ; then
      err -e $err "setup_datanode on $node:\n$out"
      return 1
    fi
    debug -e "setup_datanode on $node:\n$out"
    verbose "+++"
    verbose "+++ completed node $node with status of $err"
    return 0
  }

  # main #
  verbose "--- setup_datanode on all nodes..."

  for node in ${NODES[@]}; do
      brkmnt=${NODE_BRKMNTS[$node]} # 1 or more brk-mnt path(s)
      blkdev=${NODE_BLKDEVS[$node]} # 1 or more blk-dev path(s)
      do_node "$node" "$blkdev" "$brkmnt" || {
	  errnodes+="$node ";
	  ((errcnt++)); }
  done

  if (( ! YARN_INSIDE )) ; then
    verbose "setting up $YARN_NODE as the yarn-master server..."
    do_node $YARN_NODE || ((errcnt++)) # blkdev and brkmnt are blank
  fi

  if (( errcnt > 0 )) ; then
    err "total setup_datanode errors: $errcnt"
    return 1
  fi
  verbose "--- setup_datanode completed on all nodes..."
  return 0
}

# pool_exists: return 0 if the trusted storage pool exists, else 1.
# Uses globals:
#   FIRST_NODE
function pool_exists() {

  local ssh; local out; local err

  [[ "$FIRST_NODE" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $FIRST_NODE" 
  out="$(eval "$ssh gluster peer status")"
  err=$?
  debug "gluster peer status: $out"
  (( err != 0 )) && return 1

  # peer status returns 0 even when no pool exists, so parse output
  grep -qs 'Peers: 0' <<<$out && return 1
  return 0
}

# uniq_nodes: find the unique nodes in the list of nodes provided and set the 
# passed-in variable name to this list. 
# Args:
#   1=variable *name* to hold list of uniq nodes
#   2+=list of nodes
# Sets globals:
#   <varname in $1>
function uniq_nodes() {

  local varname=$1; shift
  local nodes=($@)
  local node; local uniq=()
  
  for node in ${nodes[*]}; do
      [[ "${uniq[*]}" =~ $node ]] && continue
      uniq+=($node)
  done

  # set passed-in global var to $uniq array
  eval "$varname=(${uniq[*]})"
}
    
# define_pool: If the trusted pool already exists then figure out which nodes are
# new (can be none) and assign them to the global POOL array, which is used for
# the gluster peer probe. Returns 1 if it's not ok to add node(s) to the pool.
# In all other cases 0 is returned.
# Args:
#   $@=list of nodes
# Uses globals:
#   AUTO_YES
#   PREFIX
# Sets globals:
#   FIRST_NODE
#   POOL
function define_pool() {

  local nodes=($@)
  local node; local uniq=()

  verbose "--- defining storage pool..."

  if pool_exists ; then
    verbose "storage pool exists"

    # find all nodes in trusted pool
    POOL=($($PREFIX/bin/find_nodes.sh -n $FIRST_NODE)) # nodes in existing pool
    FIRST_NODE=${POOL[0]} # peer probe from this node
    debug "existing pool nodes: ${POOL[@]}"

    # find nodes in pool that are not supplied nodes (ie. unique)
    for node in ${nodes[@]}; do
	[[ "${POOL[*]}" =~ $node ]] && continue
	uniq+=($node)
    done

    # are we adding nodes, or just checking existing nodes?
    POOL=(${uniq[@]}) # nodes to potentially add to existing pool, can be 0
    debug "unique nodes to add to pool: ${POOL[@]}"

    if (( ${#uniq[@]} > 0 )) ; then # we have nodes not in pool
      echo
      force -e "The following nodes are not in the existing storage pool:\n  ${uniq[@]}"
      (( ! AUTO_YES )) && ! yesno  "  Add nodes? [y|N] " && return 1 # will exit
    else # no unique nodes
      quiet "No new nodes being added so checking/setting up existing nodes..."
    fi

  else # no pool
    quiet "Will create a storage pool consisting of ${#nodes[@]} new nodes..."
    POOL=(${nodes[@]})
  fi

  return 0
}

# create_pool: create the trusted pool or add new nodes to the existing pool.
# Note: gluster peer probe returns 0 if the node is already in the pool. It
#   returns 1 if the node is unknown.
# Uses globals:
#   FIRST_NODE
#   POOL
function create_pool() {

  local node; local err; local errcnt=0; local out

  verbose "--- creating trusted storage pool..."

  # create or add-to storage pool
  for node in ${POOL[*]} ; do
      [[ "$node" == "$FIRST_NODE" ]] && continue # skip
      out="$(ssh $FIRST_NODE "gluster peer probe $node 2>&1")"
      err=$?
      if (( err != 0 )) ; then
	err -e $err "gluster peer probe $node (from $FIRST_NODE):\n$out"
	((errcnt++))
      else
        debug -e "gluster peer probe $node (from $FIRST_NODE):\n$out"
      fi
  done

  (( errcnt > 0 )) && return 1
  verbose "--- trusted storage pool created"
  return 0
}

# ambari_server: install and start the ambari server on the MGMT_NODE. Returns
# 1 on errors.
# ASSUMPTION: 1) bin/* has been copied to /tmp on all nodes
# Uses globals:
#   MGMT_NODE
function ambari_server() {

  local err; local out; local ssh

  verbose "--- installing ambari-server on $MGMT_NODE... this can take time"

  [[ "$MGMT_NODE" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $MGMT_NODE"

  out="$(eval "$ssh /tmp/bin/setup_ambari_server.sh")"
  err=$?
  if (( err != 0 )) ; then
    err -e $err "setting up ambari-sever on $MGMT_NODE:\n$out"
    return 1
  fi
  debug "setup_ambari_server: $out"

  verbose "--- install of ambari-server completed on $MGMT_NODE"
  return 0 
}

# verify_gid_uids: checks that the UIDs and GIDs for the hadoop users and hadoop
# group are the same numeric value across all of the passed-in nodes. Returns 1
# on inconsistency errors.
# Uses globals:
#   PREFIX
function verify_gid_uids() {

  local nodes="$@"
  local errcnt=0; local out; local err

  verbose "--- verifying consistent hadoop UIDs and GIDs across nodes..."

  out="$($PREFIX/bin/check_gids.sh $nodes)"
  err=$?
  debug "check_gids: $out"
  if (( err != 0 )) ; then
    ((errcnt++))
    err "inconsistent GIDs: $out"
  fi

  out="$($PREFIX/bin/check_uids.sh $nodes)"
  err=$?
  debug "check_uids: $out"
  if (( err != 0 )) ; then
    ((errcnt++))
    err "inconsistent UIDs: $out"
  fi

  (( errcnt > 0 )) && return 1
  verbose "--- completed verifying hadoop UIDs and GIDs"
  return 0
} 


## main ##

ME="$(basename $0 .sh)"
NODES=()
declare -A NODE_BRKMNTS; declare -A NODE_BLKDEVS
MGMT_INSIDE=0 # assume false
YARN_INSIDE=0 # assume false
AUTO_YES=0    # assume false
VERBOSE=$LOG_QUIET # default
errnodes=''; errcnt=0

quiet '***'
quiet "*** $ME: version $(cat $PREFIX/VERSION)"
quiet '***'

parse_cmd $@ || exit -1

default_nodes MGMT_NODE 'management' YARN_NODE 'yarn-master' || exit -1

# extract nodes, brick mnts and blk devs arrays from NODE_SPEC
parse_nodes_brkmnts_blkdevs || exit -1

# use the first storage node for all gluster cli cmds
FIRST_NODE=${NODES[0]}

# for cases where storage nodes are repeated and/or the mgmt and/or yarn nodes
# are inside the pool, there is some improved efficiency in reducing the nodes
# to just the unique nodes
uniq_nodes UNIQ_NODES ${NODES[*]} $YARN_NODE $MGMT_NODE # sets UNIQ_NODES var

# check for passwordless ssh connectivity to nodes
check_ssh ${UNIQ_NODES[*]} || exit 1

show_todo

# figure out which nodes, if any, will be added to the storage pool
define_pool ${NODES[*]} || exit 1

# prompt to continue before any changes are made...
(( ! AUTO_YES )) && ! yesno "  Continue? [y|N] " && exit 0

# copy bin/* files to /tmp/ on all nodes including mgmt- and yarn-nodes
copy_bin ${UNIQ_NODES[*]} || exit 1

# distribute and install the rhs-hadoop repo file to all nodes
install_repo ${UNIQ_NODES[*]} || exit 1

# setup each node for hadoop workloads
setup_nodes || exit 1

# if we have nodes to add then create/add-to the trusted storage pool
if (( ${#POOL[@]} > 0 )) ; then
  create_pool || exit 1
fi

# install and start the ambari server on the MGMT_NODE
ambari_server || exit 1

# verify user UID and group GID consistency across the cluster
verify_gid_uids ${UNIQ_NODES[*]} || exit 1

quiet "All nodes verified/setup for hadoop workloads with no errors"
exit 0
