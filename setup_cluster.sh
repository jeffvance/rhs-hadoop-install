#!/bin/bash
#
# TODO:
# 1) distribute the repo to each node and yum install it to get rhs-hadoop and
#    rhs-hadoop-install
# 2) logging
# 3) CDN register each node, including yarn and mgmt nodes
# 4) option to skip setting up default ports
# 5) wait for nodes to join trusted pool
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
              <nodes-spec-list>
where:

  <node-spec-list> : a list of two or more <node-spec>s.
  <node-spec> : a storage node followed by a ':', followed by a brick mount path,
      followed by another ':', followed by a block device path. Eg:
         <node1><:brickmnt1>:<blkdev1>  <node2>[:<brickmnt2>][:<blkdev2>] ...
      Each node is expected to be separate from the management and yarn-master
      nodes. Only the brick mount path and the block device path associated with
      the first node are required. If omitted from the other <node-spec-list>
      members then each node assumes the values of the first node for brick
      mount path and block device path. If a brick mount path is omitted but a
      block device path is specified then the block device path is proceded by
      two ':'s, eg. "<nodeN>::<blkdevN>"
  --yarn-master : (optional) hostname or ip of the yarn-master server which is
      expected to be outside of the storage pool. Default is localhost.
  --hadoop-mgmt-node : (optional) hostname or ip of the hadoop mgmt server which
      is expected to be outside of the storage pool. Default is localhost.
  -y : auto answer "yes" to all prompts. Default is to be promoted before the
      script continues.
  --version : output only the version string.
  --help : this text.

EOF
}

# parse_cmd: use get_opt to parse the command line. Returns 1 on errors.
# Sets globals:
#   AUTO_YES
#   MGMT_NODE
#   NODE_SPEC
#   YARN_NODE
function parse_cmd() {

  local opts='y'
  local long_opts='help,version,yarn-master:,hadoop-mgmt-node:'
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
#   NODE_BLKDEVS[<node>]="<brickmnt>[,<brkmnt1>][,<brmknt2>]..."
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
#   NODES
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
      NODES+=($node)
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

  # remove last trailing comma from each node's brk/blk value
  for node in ${NODES[@]}; do
      NODE_BRKMNTS[$node]=${NODE_BRKMNTS[$node]%*,}
      NODE_BLKDEVS[$node]=${NODE_BLKDEVS[$node]%*,}
  done

  # warning if mgmt or yarn-master nodes are inside the storage pool
  if (( MGMT_INSIDE || YARN_INSIDE )) ; then
    if (( MGMT_INSIDE && YARN_INSIDE )) ; then
      echo -e "WARN: the yarn-master and hadoop management nodes are inside the storage pool\nwhich is sub-optimal."
    elif (( MGMT_INSIDE )) ; then
      echo "WARN: the hadoop management node is inside the storage pool which is sub-optimal."
    else
      echo "WARN: the yarn-master node is inside the storage pool which is sub-optimal."
    fi
    (( ! AUTO_YES )) && ! yesno  "  Continue? [y|N] " && return 1
  fi

  # warning if yarn-master == mgmt node
  if [[ "$YARN_NODE" == "$MGMT_NODE" ]] ; then
    echo "WARN: the yarn-master and hadoop-mgmt-nodes are the same which is sub-optimal."
    (( ! AUTO_YES )) && ! yesno  "  Continue? [y|N] " && return 1
  fi

  return 0
}

# install_repo: copies the repo file expected to be on the install-from node
# (localhost) to all storage nodes and to the yarn-master and ambari mgmt nodes,
# and yum installs the packages. Returns 1 for errors.
# Uses globals:
#   MGMT_NODE
#   NODES
#   YARN_NODE
function install_repo() {

  local node; local errcnt=0
  local repo_file='/etc/yum.repos.d/rhs-hadoop.repo'

  # nested function copies to and installs package on the passed-in node.
  # Returns 1 on errors.
  function cp_install() {

    local node="$1"; local err

    # copy repo file to node
    out="$(scp $repo_file $node:$repo_file)"
    err=$?
    if (( err != 0 )) ; then
      echo "ERROR $err: coping $file to $node: $out"
      return 1
    fi

    # yum install package
    out="$(ssh $node 'yum install -y --nogpgcheck rhs-hadoop')"
    err=$?
    if (( err != 0 )) ; then
      echo "ERROR $err: yum installing $file on $node: $out"
      return 1
    fi
    return 0
  }

  ## main ##

  [[ ! -f "$repo_file" ]] && {
    echo "ERROR: $repo_file is missing. Cannot install rhs-hadoop package on other nodes";
    return 1; }

  for node in ${NODES[@]}; do # all storage nodes
      [[ "$node" == "$HOSTNAME" ]] && continue # skip self (localhost)
      cp_install $node || ((errcnt++))
  done

  # install on yarn-master and mgmt nodes
  if [[ "$YARN_NODE" != "$HOSTNAME" ]] ; then
     cp_install $YARN_NODE || ((errcnt++))
  fi
  if [[ "$MGMT_NODE" != "$HOSTNAME" ]] ; then
    cp_install $MGMT_NODE || ((errcnt++))
  fi

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
    local out; local err; local ssh; local scp

    [[ "$node" == "$HOSTNAME" ]] && { ssh=''; scp='#'; } || \
                                    { ssh="ssh $node"; scp='scp'; }
    eval "$scp -r -q $PREFIX/bin $node:/tmp"
    out="$(eval "
	$ssh /tmp/bin/setup_datanode.sh --blkdev $blkdev \
		--brkmnt $brkmnt --hadoop-mgmt-node $MGMT_NODE
 	")"
    err=$?
    echo "setup_datanode for $node: $out"
    if (( $? != 0 )) ; then
      echo "ERROR: $err: in setup_datanode"
      return 1
    fi

    return 0
  }

  # main #
  for node in ${NODES[@]}; do
      brkmnt=${NODE_BRKMNTS[$node]} # 1 or more brk-mnt path(s)
      blkdev=${NODE_BLKDEVS[$node]} # 1 or more blk-dev path(s)
      do_node "$node" "$blkdev" "$brkmnt" || {
	  errnodes+="$node ";
	  ((errcnt++)); }
  done

  if (( ! YARN_INSIDE )) ; then
    do_node $YARN_NODE || ((errcnt++)) # blkdev and brkmnt are blank
  fi

  if (( errcnt > 0 )) ; then
    echo "$errcnt setup node errors on nodes: $errnodes"
    return 1
  fi

  return 0
}

# pool_exists: return 0 if the trusted storage pool exists, else 1.
# Uses globals:
#   FIRST_NODE
function pool_exists() {

  local ssh; local out

  [[ "$FIRST_NODE" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $FIRST_NODE" 
  out="$(eval "$ssh gluster peer status")"
  (( $? != 0 )) && return 1

  # peer status returns 0 even when no pool exists, so parse output
  grep -qs 'Peers: 0' <<<$out && return 1
  return 0
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

  if pool_exists ; then
    echo "Storage pool exists..."
    # find all nodes in trusted pool
    POOL=($($PREFIX/bin/find_nodes.sh -n $FIRST_NODE)) # nodes in existing pool
    FIRST_NODE=${POOL[0]} # peer probe from this node

    # find nodes in pool that are not supplied nodes (ie. unique)
    for node in ${nodes[@]}; do
	[[ "${POOL[@]}" =~ $node ]] && continue
	uniq+=($node)
    done

    # are we adding nodes, or just checking existing nodes?
    POOL=(${uniq[@]}) # nodes to potentially add to existing pool, can be 0
    if (( ${#uniq[@]} > 0 )) ; then # we have nodes not in pool
      echo
      echo -e "The following nodes are not in the existing storage pool:\n  ${uniq[@]}"
      (( ! AUTO_YES )) && ! yesno  "  Add nodes? [y|N] " && return 1 # will exit
    else # no unique nodes
      echo "No new nodes being added so only verifying existing nodes..."
    fi

  else # no pool
    echo "Will create a storage pool consisting of ${#nodes[@]} new nodes..."
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

  local node; local err; local errcnt=0; local errnodes=''; local out

  # create or add-to storage pool
  for node in ${POOL[@]}; do
      [[ "$node" == "$FIRST_NODE" ]] && continue # skip
      out="$(ssh $FIRST_NODE "gluster peer probe $node")"
      err=$?
      if (( err != 0 )) ; then
	echo "ERROR $err: peer probe failed on $node"
	errnodes+="$node "
	((errcnt++))
      fi
  done

  if (( errcnt > 0 )) ; then
    echo "$errcnt peer probe errors on nodes: $errnodes"
    return 1
  fi
  return 0
}

# ambari_server: install and start the ambari server on the MGMT_NODE. Returns
# 1 on errors.
# ASSUMPTION: 1) bin/* has been copied to all storage nodes but has not been
#   copied to nodes outside of the pool.
# Uses globals:
#   MGMT_INSIDE
#   MGMT_NODE
function ambari_server() {

  local out; local ssh; local scp

  echo "Installing the ambari-server on $MGMT_NODE... this can take time"

  if [[ "$MGMT_NODE" == "$HOSTNAME" ]] ; then # all scripts in place
    $PREFIX/bin/setup_ambari_server.sh || return 1
  else 
    # if the mgmt-node is inside the storage pool then all bin scripts have been
    # copied, else need to copy the setup_ambari_server script
    (( MGMT_INSIDE )) || scp -q -r $PREFIX/bin $MGMT_NODE:/tmp
    # setup the ambari server on the mgmt-node
    ssh $MGMT_NODE "/tmp/bin/setup_ambari_server.sh" || return 1
  fi

  return 0 
}


## main ##

ME="$(basename $0 .sh)"
NODES=()
declare -A NODE_BRKMNTS; declare -A NODE_BLKDEVS
MGMT_INSIDE=0 # assume false
YARN_INSIDE=0 # assume false
AUTO_YES=0    # assume false
errnodes=''; errcnt=0

echo '***'
echo "*** $ME: version $(cat $PREFIX/VERSION)"
echo '***'

parse_cmd $@ || exit -1

default_nodes MGMT_NODE 'management' YARN_NODE 'yarn-master' || exit -1

# extract nodes, brick mnts and blk devs arrays from NODE_SPEC
parse_nodes_brkmnts_blkdevs || exit -1
# use the first storage node for all gluster cli cmds
FIRST_NODE=${NODES[0]}

# check for passwordless ssh connectivity to nodes
check_ssh ${NODES[@]} || exit 1

echo
echo "*** Nodes             : ${NODES[@]}"
echo "*** Brick mounts      :"
for node in ${NODES[@]}; do
    echo "      $node         : ${NODE_BRKMNTS[$node]}"
done
echo "*** Block devices     :"
for node in ${NODES[@]}; do
    echo "      $node         : ${NODE_BLKDEVS[$node]}"
done
echo "*** Ambari mgmt node  : $MGMT_NODE"
echo "*** Yarn-master server: $YARN_NODE"
echo

# figure out which nodes, if any, will be added to the storage pool
define_pool ${NODES[@]} || exit 1

# prompt to continue before any changes are made...
(( ! AUTO_YES )) && ! yesno "  Continue? [y|N] " && exit 0

# distribute and install the rhs-hadoop repo file to all nodes
install_repo || exit 1

# setup each node for hadoop workloads
setup_nodes || exit 1

# if we have nodes to add then create/add-to the trusted storage pool
if (( ${#POOL[@]} > 0 )) ; then
  create_pool || exit 1
fi

# install and start the ambari server on the MGMT_NODE
ambari_server || exit 1

echo "All nodes verified/setup for hadoop workloads with no errors"
exit 0
