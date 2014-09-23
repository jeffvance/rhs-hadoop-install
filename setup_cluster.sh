#!/bin/bash
#
# TODO:
# 1) verify brick xfs mount options, eg. noatime
# 2) wait for nodes to join trusted pool
#
# setup_cluster.sh accepts a list of nodes:brick-mnts:block-devs, along with
# the name of the yarn-master and hadoop-mgmt servers, and does one of three
# things:
#  - creates a new trusted storage pool if none exists, or
#  - if a pool already exists then adds the supplied nodes to the storage pool,
#    (referred to as "scaling up"),  or
#  - if a pool already exists and the supplied nodes are in that pool then re-
#    validate the supplied nodes. Re-validating consists of redoing the steps
#    to setup the desired environment, and these steps are idempotent.
#
# The yarn and mgmt nodes are expected to be rhel 6.5 servers outside of the
# pool, and not to be the same server; however, these recommendations are not
# enforced by the script.
#
# On each rhs node the blk-device is setup as an xfs file system and mounted to
# the brick mount dir, ntp config is verified, iptables are disabled, selinux
# is set to permissive, and the required hadoop local directories are created
# (note: the required Hadoop distributed dirs are not created here). If a
# profile is specified then that profile will be set by tuned-adm.
#
# Also, on all passed-in nodes (assumed to be storage nodes) and on the yarn-
# master server node, the ambari agent is installed (updated if present) and
# started. If the hadoop management node is outside of the storage pool then it
# will not have the agent installed. Last, the ambari-server is installed and
# started on the mgmt-node.
#
# Tasks related to volumes are not done here.
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

$ME [-y] [--hadoop-mgmt-node <node>] [--yarn-master <node>] \\
              [--profile <profile>] [--quiet | --verbose | --debug] \\
              <nodes-spec-list>
where:

<nodes-spec-list>: a list of two or more <node-spec's>.
<node-spec>     : a storage node followed by a ':', followed by a brick mount
                  path, followed by another ':', followed by a block device
                  path.
                  Eg: <node1><:brickmnt1>:<blkdev1> <node2>[:<brickmnt2>]
                      [:<blkdev2>] [<node3>] ...
                  Only the brick mount path and the block device path associated
                  with the first node are required. If omitted from the other
                  <nodes-spec-list>'s then each node assumes the values of the
                  first node for brick mount path and block device path. If a
                  brick mount path is omitted but a block device path is
                  specified then the block device path is proceded by two ':'s,
                  e.g., "<nodeN>::<blkdevN>". It is recommended that the mgmt
                  and yarn-master nodes are not also storage nodes and are not
                  the same server.
--yarn-master   : (optional) hostname or ip of the yarn-master server which is
                  expected to be outside of the storage pool. Default is
                  localhost.
--hadoop-mgmt-node: (optional) hostname or ip of the hadoop mgmt server which
                  is expected to be outside of the storage pool. Default is
                  localhost.
--profile       : (optional) the name of a supported rhs/kernel profile, eg.
                  "rhs-high-throughput". Default is not set a profile.
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
#   PROFILE
#   VERBOSE
#   YARN_NODE
function parse_cmd() {

  local opts='y'
  local verbose_opts='verbose,quiet,debug'   # default= --quiet
  local node_opts='hadoop-mgmt-node:,yarn-master:'
  local long_opts="help,version,profile:,$node_opts,$verbose_opts"
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
	--profile)
	  PROFILE="$2"; shift 2; continue
	;;
	--)
	  shift; break
	;;
      esac
  done

  # check required args
  NODE_SPEC=($@) # array of nodes, brick-mnts, blk-devs -- each separated by ":"
  if [[ -z "$NODE_SPEC" ]] || (( ${#NODE_SPEC[@]} < 2 )) ; then
    echo "Syntax error: expect list of 2 or more nodes plus brick mount(s) and block dev(s)"
    ((errcnt++))
  fi

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
# list. A check is made to see if the management node and/or yarn-master node
# is inside the storage pool and/or are the same node, and if so a warning is
# reported and the user is prompted to continue. Returns 1 on errors and if the
# user answers no.
# Uses globals:
#   NODE_SPEC
# Sets globals:
#   NODES() *unique* storage nodes
#   NODE_BLKDEVS
#   NODE_BRKMNTS
function parse_nodes_brkmnts_blkdevs() {

  local node_spec=(${NODE_SPEC[0]//:/ }) # split after subst ":" with space
  local def_brkmnt=${node_spec[1]} # default
  local def_blkdev=${node_spec[2]} # default
  local brkmnts=(); local blkdev

  if [[ -z "$def_brkmnt" || -z "$def_blkdev" ]] ; then
    echo -e "Syntax error: expect a brick mount and block device to immediately follow the\nfirst node (each separated by a \":\")"
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
  done

  # assign unique storage nodes
  NODES=($(printf '%s\n' "${!NODE_BRKMNTS[@]}" | sort))

  # remove last trailing comma from each node's brk/blk value
  for node in ${NODES[@]}; do
      NODE_BRKMNTS[$node]=${NODE_BRKMNTS[$node]%*,}
      NODE_BLKDEVS[$node]=${NODE_BLKDEVS[$node]%*,}
  done

  return 0
}

# check_yarn_ambari_nodes: check if the management node and/or yarn-master node
# is inside the storage pool and/or are the same node, and if so a warning is
# reported and the user is prompted to continue. Returns 1 if the user answers
# no.
# Uses globals:
#   AUTO_YES
#   YARN_NODE
#   MGMT_NODE
#   NODES()
#   NODE_IPS()
# Sets globals:
#   MGMT_INSIDE
#   YARN_INSIDE
function check_yarn_ambari_nodes() {

  local node; local ip
  local mgmt_ip="${NODE_IPS[$MGMT_NODE]}" # ip addr
  local yarn_ip="${NODE_IPS[$YARN_NODE]}" # ip addr

  # detect if yarn-master or mgmt node are inside storage pool
  for node in ${NODES[@]}; do
      ip="${NODE_IPS[$node]}"
      [[ "$ip" == "$yarn_ip" ]] && YARN_INSIDE=1 # true
      [[ "$ip" == "$mgmt_ip" ]] && MGMT_INSIDE=1 # true
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
  if [[ "$yarn_ip" == "$mgmt_ip" ]] ; then
    warn "the yarn-master and hadoop-mgmt-nodes are the same which is sub-optimal."
    (( ! AUTO_YES )) && ! yesno  "  Continue? [y|N] " && return 1
  fi

  return 0
}

# check_blkdevs: check that the list of block devices are likely to be block
# devices. Returns 1 on errors.
# Uses globals:
#   NODES (unique storage nodes)
#   NODE_BLKDEVS
function check_blkdevs() {

  local node; local blkdev; local err; local errcnt=0; local out

  verbose "--- checking block devices..."

  for node in ${NODES[@]}; do
      out="$(ssh $node "
	  errs=0
	  for blkdev in ${NODE_BLKDEVS[$node]//,/ }; do
	      if [[ ! -e \$blkdev ]] ; then
	        echo \"\$blkdev does not exist on $node\"
	        ((errs++))
	        continue
	      fi
	      if [[ -b \$blkdev && ! -L \$blkdev ]] ; then
	        echo \"\$blkdev on $node must be a logical volume but appearsto be a raw block device. Expecting: /dev/VGname/LVname\"
	        ((errs++))
	        continue
	      fi
	  done
	  (( errs > 0 )) && exit 1 || exit 0
	")"
      err=$?
      if (( err != 0 )) ; then
	((errcnt++))
        err "$out"
      elif [[ -n "$out" ]] ; then
	debug "$out"
      fi
  done

  verbose "--- done checking block devices"
  (( errcnt > 0 )) && return 1
  return 0
}

# show_todo: show summary of actions that will be done.
# Uses globals:
#   BLKDEVS
#   BRKMNTS
#   MGMT_NODE
#   NODES
#   YARN_NODE
function show_todo() {

  local node; local fmt_node; local fill

  echo
  quiet "*** Nodes              : $(echo ${NODES[*]} | sed 's/ /, /g')"
  quiet "*** Brick mounts"
  for node in ${NODES[@]}; do
      let fill=(16-${#node}) # to left-justify node
      fmt_node="$node $(printf ' %.0s' $(seq $fill))"
      quiet "      $fmt_node: ${NODE_BRKMNTS[$node]//,/, }"
  done

  quiet "*** Block devices"
  for node in ${NODES[@]}; do
      let fill=(16-${#node}) # to left-justify node
      fmt_node="$node $(printf ' %.0s' $(seq $fill))"
      quiet "      $fmt_node: ${NODE_BLKDEVS[$node]//,/, }"
  done

  quiet "*** Ambari mgmt node   : $MGMT_NODE"
  quiet "*** Yarn-master server : $YARN_NODE"
  echo
}

# check_bin_dir: checks that the bin/ dir exists in the expected location on
# all passed-in nodes. Returns 1 on errors.
# Uses globals:
#   PREFIX
function check_bin_dir() {

  local node; local errcnt=0; local ssh
  local bin_path="$PREFIX/bin"

  verbose "--- checking that $bin_path/ exists on all nodes..."

  for node in $@; do
      [[ "$node" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $node"
      eval "$ssh [[ -d $bin_path ]]"
      if (( $? != 0 )) ; then
	err "$bin_path/ not found on $node"
	((errcnt++))
      else
	debug "$bin_path/ found on $node"
      fi
  done

  (( errcnt > 0 )) && return 1
  verbose "--- done checking that $bin_path/ exists on all nodes"
  return 0
}

# nodes_to_ips: set the global NODE_IPS variable which contains the ip address
# for all nodes specified by the user, eg. rhs storage nodes, yarn-master node,
# and ambari mgmt node. Typically each node is a hostname rather than an ip
# address. If the passed-in node is already an ip address it is still added to
# the NODE_IPS array.
# Assumption: the list of passed-in nodes is *unique*, that way the output has
#   only 1 ip-addr as the value of each node.
# Sets globals:
#   NODE_IPS() # assoc array: key=hostname, value=ip-addr
function nodes_to_ips() {

  local nodes="$@"
  local node

  for node in $nodes; do
      NODE_IPS[$node]="$(hostname_to_ip $node)"
      (( $? != 0 )) && warn "$node could not be converted to an ip address"
  done

  return 0
}

# prep_rhel_nodes: perform the tasks, if any, for the rhel nodes. Typically,
# these would be the mgmt and yarn nodes. Returns 1 on errors.
# Currently, the only special prep for rhel nodes is upgrading openssl.
# Args: $@=list of potential rhel nodes.
function prep_rhel_nodes() {

  local rhel_nodes="$@"
  local node; local ssh; local ssh_close
  local err; local errcnt=0; local out

  verbose "--- prepping rhel nodes..."

  for node in $rhel_nodes; do
      [[ "$node" == "$HOSTNAME" ]] && { ssh=''; ssh_close=''; } \
				   || { ssh="ssh $node '"; ssh_close="'"; }
      out="$(eval "$ssh 
	     if [[ -f /etc/redhat-storage-release ]] ; then
	       echo \"RHS node: no openssl upgrade needed...\"
	     else
	       echo \"RHEL node...\"
	       yum -y upgrade openssl 2>&1
	     fi
	     $ssh_close "
	  )"
      err=$?
      debug "yum upgrade openssl on $node: $out"
      if (( err != 0 )) ; then
	err $err "yum upgrade openssl on $node"
	(( errcnt++ ))
      fi
  done

  (( errcnt > 0 )) && return 1
  verbose "--- done prepping rhel nodes"
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
#   PROFILE
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
	$ssh $PREFIX/bin/setup_datanode.sh --blkdev $blkdev --brkmnt $brkmnt \
		--profile $PROFILE --hadoop-mgmt-node $MGMT_NODE
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
      brkmnt="${NODE_BRKMNTS[$node]}" # 1 or more brk-mnt path(s)
      blkdev="${NODE_BLKDEVS[$node]}" # 1 or more blk-dev path(s)
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

# pool_exists: returns true (shell 0) if a trusted storage pool exists, else
# returns false (1). Determining if a pool exists is tricky since the nodes
# passed to setup_cluster may be nodes used to expand an existing pool; however,
# none of the supplied nodes are in the pool yet, hence gluster peer status 
# will return 0 and number of nodes 0. This would make us conclude that there
# is not a storage pool; however, it only means that from the node used to 
# execute the peer status (FIRST_NODE) there is no pool. The solution is that
# if peer status indicates that no pool exists then we need to ssh to the
# yarn-node and extract the gluster-fuse mount node, if it exists. Then we
# can re-execute peer status from this node. If the pool exists then FIRST_NODE
# is set to the node used to execute peer status from.
# Uses globals:
#   FIRST_NODE
#   YARN_NODE
# Sets globals:
#   FIRST_NODE (only if the pool exists)
function pool_exists() {

  local out; local err

  # nested function which executes gluster peer status from the passed-in node.
  # Returns 0 if a pool exists, else returns 1.
  function peer_status() {

    local node=$1
    local ssh; local out; local err

    [[ "$node" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $node" 

    out="$(eval "$ssh gluster peer status")"
    err=$?
    debug "gluster peer status: $out"
    (( err != 0 )) && return 1 # no pool

    # peer status returns 0 even when no pool exists, so parse output
    grep -qs 'Peers: 0' <<<$out && return 1 # no pool
    return 0 # pool exists
  }

  # nested function which extracts the node used in a glusterfs-fuse mount
  # from /etc/fstab on the yarn-node. Sets FIRST_NODE to this node if found.
  # Returns 1 if a glusterfs-fuse mount exists, else returns 0.
  function node_from_yarn_mnt() {

    local node

    # extract node from glusterfs-fuse mount if it exists
    node="$(ssh $YARN_NODE "grep -m 1 ' glusterfs ' /etc/fstab | cut -d: -f1")"
    [[ -z "$node" ]] && {
      debug "no glusterfs-fuse mount found on yarn-master ($YARN_NODE)";
      return 1; } # no pool

    debug "found node $node in /etc/fstab on $YARN_NODE"
    # set FIRST_NODE to node and return 0 (true)
    FIRST_NODE=$node
    return 0
  }

  ## main
  peer_status $FIRST_NODE && return 0 # pool exists

  # maybe no pool; see if a volume is mounted on the known yarn-node
  node_from_yarn_mnt || return 1 # no pool
  # note: FIRST_NODE has been set from call above
  peer_status $FIRST_NODE && return 0 # pool exists
  return 1 # no pool
}

# define_pool: if the trusted pool already exists then figure out which nodes
# are new (can be none) and assign them to the global POOL array, which is used
# for the gluster peer probe. Returns 1 if the user answers that it's not ok to
# add node(s) to the pool. In all other cases 0 is returned.
# Args:
#   $@=list of nodes
# Uses globals:
#   AUTO_YES
#   FIRST_NODE
#   NODE_IPS()
#   PREFIX
# Sets globals:
#   POOL() # ip addresses for all storage nodes
function define_pool() {

  local nodes=($@)
  local i; local node; local uniq=(); local msg='(none)'

  verbose "--- defining storage pool..."

  if pool_exists ; then
    verbose "storage pool exists"

    # find all nodes in trusted pool
    POOL=($($PREFIX/bin/find_nodes.sh -n $FIRST_NODE -u))
    debug "existing pool nodes: ${POOL[*]}"

    # convert entire pool array to ip addresses
    for (( i=0; i<${#POOL[*]}; i++ )); do
	POOL[$i]=$(hostname_to_ip ${POOL[$i]})
    done
    debug "existing pool nodes after converted to ip's: ${POOL[*]}"

    # find nodes in pool that are not supplied $nodes (ie. unique)
    for node in ${nodes[@]}; do
	[[ "${POOL[*]}" =~ ${NODE_IPS[$node]} ]] && continue
	uniq+=($node)
    done

    # are we adding nodes, or just checking existing nodes?
    POOL=(${uniq[@]}) # nodes to potentially add to existing pool, can be 0
    (( ${#POOL[*]} > 0 )) && msg="${POOL[*]}"
    debug "unique nodes to add to pool: $msg"

    if (( ${#uniq[@]} > 0 )) ; then # we have nodes not in pool
      force -e "The following nodes are not in the existing storage pool:\n  ${uniq[*]}"
      (( ! AUTO_YES )) && ! yesno  "  Add nodes? [y|N] " && return 1 # will exit
    else # no unique nodes
      quiet "No new nodes being added so checking/setting up existing nodes..."
    fi

  else # no pool
    quiet "Will create a storage pool consisting of ${#nodes[*]} new nodes..."
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

# ambari_server: install and start the ambari server on the MGMT_NODE. This
# includes installation and starting of ambari-server, setting selinux to
# permissive mode, and disabling the firewall on the ambari-server. Returns 1
# on errors.
# Uses globals:
#   MGMT_NODE
#   PREFIX
function ambari_server() {

  local err; local out; local ssh

  verbose "--- installing ambari-server on $MGMT_NODE... this can take time"

  [[ "$MGMT_NODE" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $MGMT_NODE"

  out="$(eval "$ssh $PREFIX/bin/setup_ambari_server.sh")"
  err=$?
  if (( err != 0 )) ; then
    err -e $err "setting up ambari-sever on $MGMT_NODE:\n$out"
    return 1
  fi
  debug "setup_ambari_server: $out"

  verbose "--- install of ambari-server completed on $MGMT_NODE"
  return 0 
}

# update_yarn: yum installs the latest glusterfs client bits on the yarn node
# if the gluster client version is older than 3.6. The yarn node is expected to
# be a RHEL 6.5 server, but it could be a storage node. Returns 1 for errors.
# Uses globals:
#   YARN_INSIDE
#   YARN_NODE
function update_yarn() {

  local out; local err
  local major; local minor; local fix
  local channel='rhel-x86_64-server-rhsclient-6'
  local gluster_rpms='glusterfs glusterfs-api glusterfs-fuse glusterfs-libs'

  # nested function that extracts the glusterfs major, minor, and fix level
  # from the passed-in long version string. Sets these variables.
  function gluster_version() {

    local ver=(${1//./ }) # easy convert to array

    major=${ver[0]} # main function local
    minor=${ver[1]} # main function local
    fix=${ver[2]}   # main function local
    debug "glusterfs version on yarn-master ($YARN_NODE): ${major}.${minor}.$fix"
  }

  ## main
  (( YARN_INSIDE )) && return 0 # rhs nodes have the correct client bits

  # which glusterfs version is installed on the yarn-node
  out=($(ssh $YARN_NODE "yum list installed glusterfs 2>&1 | \
	grep ^glusterfs | \
	head -n 1"))
  if (( ${#out[*]} > 0 )) ; then # see if current enough version is installed
    gluster_version "${out[1]}" # sets major/minor/fix variables
    if (( major > 3 || ( major == 3 && minor >= 6 ) )) ; then # 3.6+
      verbose "--- yarn-master ($YARN_NODE) has the correct glusterfs client version"
      return 0 # no need to update glusterfs
    else
      debug "installed glusterfs client version on $YARN_NODE is pre 3.6 and needs updating"
    fi
  else
    debug "no installed glusterfs client packages on $YARN_NODE"
  fi

  # check available glusterfs packages
  out=($(ssh $YARN_NODE "yum list available glusterfs 2>&1 | \
        grep ^glusterfs | \
        head -n 1"))
  if (( ${#out[*]} == 0 )) ; then
    err -e "unable to find any glusterfs packages to install on the yarn-master ($YARN_NODE).\nEnsure that the client channel \"$channel\" has been added"
    return 1
  fi

  # we have available glusterfs pkg but is it 3.6+?
  gluster_version "${out[1]}" # sets major/minor/fix local vars
  if (( major < 3 || ( major == 3 && minor < 6 ) )) ; then
    err -e "the available glusterfs client packages are older than 3.6 and therefore should not be yum installed on the yarn-master ($YARN_NODE).\nEnsure that the client channel \"$channel\" has been added"
    return 1
  fi

  verbose "--- updating yarn-master ($YARN_NODE) to gluster client ${major}.${minor}.$fix ..."

  out="$(ssh $YARN_NODE "yum -y install $gluster_rpms 2>&1")"
  err=$?
  if (( err != 0 )) ; then
    err $err "yum install $gluster_rpms: $out"
    return 1
  fi

  debug "yum install $gluster_rpms: $out"
  verbose "--- done updating $YARN_NODE to latest gluster client bits"
  return 0
}


## main ##

ME="$(basename $0 .sh)"
NODES=()
declare -A NODE_IPS; declare -A NODE_BRKMNTS; declare -A NODE_BLKDEVS
MGMT_INSIDE=0		# assume false
YARN_INSIDE=0		# assume false
AUTO_YES=0		# assume false
VERBOSE=$LOG_QUIET	# default
errnodes=''; errcnt=0

report_version $ME $PREFIX

parse_cmd $@ || exit -1

default_nodes MGMT_NODE 'management' YARN_NODE 'yarn-master' || exit -1

# extract nodes, brick mnts and blk devs arrays from NODE_SPEC
parse_nodes_brkmnts_blkdevs || exit -1

# for cases where storage nodes are repeated and/or the mgmt and/or yarn nodes
# are inside the pool, there is some improved efficiency in reducing the nodes
# to just the unique nodes
UNIQ_NODES=($(uniq_nodes ${NODES[*]} $YARN_NODE $MGMT_NODE))

# create the NODE_IPS global assoc array, which contains the ip address for all
# nodes provided by the user
nodes_to_ips ${UNIQ_NODES[*]}
debug "ips for nodes (${!NODE_IPS[*]}): (${NODE_IPS[*]})"

# check if the yarn and/or mgmt nodes are the same and/or in the storage pool
check_yarn_ambari_nodes || exit -1

# use the first storage node for all gluster cli cmds
FIRST_NODE=${NODES[0]}

# check for passwordless ssh connectivity to nodes
check_ssh ${UNIQ_NODES[*]} || exit 1

# check that the block devs are (likely to be) block devices
check_blkdevs || exit 1

# ensure bin/ dir is found on all nodes including mgmt, yarn and localhost
check_bin_dir $(uniq_nodes ${UNIQ_NODES[*]} $HOSTNAME) || exit 1

# verify user UID and group GID consistency across the cluster
verify_gid_uids ${NODES[*]} $YARN_NODE || exit 1 

show_todo

# figure out which nodes, if any, will be added to the storage pool
define_pool ${NODES[*]} || exit 1  # sets POOL() global

# prompt to continue before any changes are made...
(( ! AUTO_YES )) && ! yesno "  Continue? [y|N] " && exit 0

echo
echo "*** begin cluster setup... this may take some time..."
(( VERBOSE > LOG_DEBUG )) && echo "    see $LOGFILE to view progress..."
echo

# do any special steps needed for rhel-only nodes, not needed for rhs nodes
prep_rhel_nodes $(uniq_nodes $YARN_NODE $MGMT_NODE) || exit 1

# setup each node for hadoop workloads
setup_nodes || exit 1

# if we have nodes to add then create/add-to the trusted storage pool
if (( ${#POOL[@]} > 0 )) ; then
  create_pool || exit 1
fi

# install and start the ambari server on the MGMT_NODE
ambari_server || exit 1

# set up yarn-master with the correct glusterfs bits
update_yarn || exit 1

quiet "All nodes verified/setup for hadoop workloads with no errors"
exit 0
