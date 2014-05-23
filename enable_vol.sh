#!/bin/bash
#
# enable_vol.sh accepts a volume name, discovers and checks the volume mount on
# each node spanned by the volume to be sure they are setup for hadoop workloads,
# and then updates the core-site file to contain the volume. 
#
# See usage() for syntax.

PREFIX="$(dirname $(readlink -f $0))"

## functions ##

source $PREFIX/bin/functions

# usage: output the general description and syntax.
function usage() {

  cat <<EOF

$ME enables an existing RHS volume for hadoop workloads.

SYNTAX:

$ME --version | --help

$ME [-y] [--user <ambari-admin-user>] [--pass <ambari-admin-password>] \\
           [--port <port-num>] [--hadoop-management-node <node>] \\
           [--rhs-node <node>] [--yarn-master <node>] <volname>
where:

  <volname> : the RHS volume to be enabled for hadoop workloads.
  --yarn-master : (optional) hostname or ip of the yarn-master server which is
      expected to be outside of the storage pool. Default is localhost.
  --rhs_node : (optional) hostname of any of the storage nodes. This is needed in
      order to access the gluster command. Default is localhost which, must have
      gluster cli access.
  --hadoop-mgmt-node : (optional) hostname or ip of the hadoop mgmt server which
      is expected to be outside of the storage pool. Default is localhost.
  -y : auto answer "yes" to all prompts. Default is to be promoted before the
      script continues.
  --user : the ambari admin user name. Default: "admin".
  --pass : the password for --user. Default: "admin".
  --port : the port number used by the ambari server. Default: 8080.
  --version : output only the version string.
  --help : this text.

EOF
}

# parse_cmd: simple positional parsing. Returns 1 on errors.
# Sets globals:
#   AUTO_YES
#   MGMT_NODE
#   MGMT_PASS
#   MGMT_PORT
#   MGMT_USER
#   RHS_NODE
#   VOLNAME
#   YARN_NODE
function parse_cmd() {

  local opts='y'
  local long_opts='version,help,yarn-master:,rhs-node:,hadoop-mgmt-node:,user:,pass:,port:'
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
          AUTO_YES=1; shift; continue # true
        ;;
        --yarn-master)
          YARN_NODE="$2"; shift 2; continue
        ;;
        --rhs-node)
          RHS_NODE="$2"; shift 2; continue
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

  # check for required args and options
  [[ -z "$VOLNAME" ]] && {
    echo "Syntax error: volume name is required";
    ((errcnt++)); }

  return 0
}

# setup_nodes: setup each node for hadoop workloads by invoking
# setup_datanodes.sh. Returns 1 on errors.
# Uses globals:
#   BLKDEVS
#   BRKMNTS
#   MGMT_NODE
#   NODES
#   PREFIX
#   YARN_NODE
function setup_nodes() {

  local i=0; local err; local errcnt=0; local errnodes=''
  local node; local brkmnt; local blkdev; local ssh; local scp

  for node in ${NODES[@]}; do
      brkmnt=${BRKMNTS[$i]}
      blkdev=${BLKDEVS[$i]}

      [[ "$node" == "$HOSTNAME" ]] && { ssh=''; scp='#'; } || \
				       { ssh="ssh $node"; scp='scp'; }
      eval "$scp -r -q $PREFIX/bin $node:/tmp"
      eval "$ssh /tmp/bin/setup_datanode.sh --blkdev $blkdev \
		--brkmnt $brkmnt --hadoop-mgmt-node $MGMT_NODE"
      err=$?
      if (( err != 0 )) ; then
        echo "ERROR $err: setup_datanode failed on $node"
        errnodes+="$node "
        ((errcnt++))
      fi
      ((i++))
  done

  (( errcnt > 0 )) && {
    echo "$errcnt setup node errors on nodes: $errnodes";
    return 1; }
  return 0
}

# chk_and_fix_nodes: this is the first opportunity to setup the yarn-master 
# server because we need both the yarn-master node and a volume. Next, check_vol
# is called to verify that VOLNAME has been setup for hadoop workloads, including
# each node spanned by the volume. If setup issues are detected then the user is
# optionally prompted to fix the problems. Returns 1 for errors.
# Uses globals:
#   AUTO_YES
#   PREFIX
#   RHS_NODE
#   VOLNAME
function chk_and_fix_nodes() {

  local errcnt=0

  # setup the yarn-master node
  $PREFIX/bin/setup_yarn.sh -n $RHS_NODE -y $YARN_NODE $VOLNAME || ((errcnt++))

  # verify that the volume is setup for hadoop workload and potentially fix
  if ! $PREFIX/bin/check_vol.sh -n $RHS_NODE -y $YARN_NODE $VOLNAME ;
  then # problems
    echo
    echo "Nodes spanned by $VOLNAME and/or the YARN-master node have issues"
    if (( AUTO_YES )) || yesno "  Correct above issues? [y|N] " ; then
      echo
      setup_nodes || ((errcnt++))
      $PREFIX/bin/set_vol_perf.sh -n $RHS_NODE $VOLNAME || ((errcnt++))
    else
      ((errcnt++))
    fi
  fi

  (( errcnt > 0 )) && return 1
  return 0
}

# edit_core_site: invoke bin/set_glusterfs_uri to edit the core-site file and
# restart all ambari services across the cluster. Returns 1 on errors.
# Uses globals:
#   MGMT_*
#   PREFIX
#   VOLNAME
function edit_core_site() {

  local mgmt_u; local mgmt_p; local mgmt_port

  echo "Enable $VOLNAME in all core-site.xml files..."

  [[ -n "$MGMT_USER" ]] && mgmt_u="-u $MGMT_USER"
  [[ -n "$MGMT_PASS" ]] && mgmt_p="-p $MGMT_PASS"
  [[ -n "$MGMT_PORT" ]] && mgmt_port="--port $MGMT_PORT"

  $PREFIX/bin/set_glusterfs_uri.sh -h $MGMT_NODE $mgmt_u $mgmt_p $mgmt_port \
	 $VOLNAME || return 1

  return 0
}


## main ##

ME="$(basename $0 .sh)"
errcnt=0
AUTO_YES=0 # false

echo '***'
echo "*** $ME: version $(cat $PREFIX/VERSION)"
echo '***'

parse_cmd $@ || exit -1

default_nodes MGMT_NODE 'management' YARN_NODE 'yarn-master' \
	RHS_NODE 'RHS storage' || exit -1

vol_exists $VOLNAME $RHS_NODE || {
  echo "ERROR volume $VOLNAME does not exist";
  exit 1; }

NODES=($($PREFIX/bin/find_nodes.sh -n $RHS_NODE $VOLNAME)) # spanned by vol
if (( $? != 0 )) ; then
  echo "${NODE[@]}" # from find_nodes
  exit 1
fi

# check for passwordless ssh connectivity to nodes
check_ssh ${NODES[@]} || exit 1

BRKMNTS=($($PREFIX/bin/find_brick_mnts.sh -xn $RHS_NODE $VOLNAME))
BLKDEVS=($($PREFIX/bin/find_blocks.sh -xn $RHS_NODE $VOLNAME))

echo
echo "*** Nodes             : ${NODES[@]}"
echo "*** Brick mounts      : ${BRKMNTS[@]}"
echo "*** Block devices     : ${BLKDEVS[@]}"
echo "*** Ambari mgmt node  : $MGMT_NODE"
echo "*** Yarn-master server: $YARN_NODE"
echo

# prompt to continue before any changes are made...
(( ! AUTO_YES )) && ! yesno "Enabling volume $VOLNAME. Continue? [y|N] " && \
  exit 0

# verify nodes spanned by the volume are ready for hadoop workloads, and if
# not prompt user to fix problems.
chk_and_fix_nodes || exit 1

# edit the core-site file to recognize the enabled volume
edit_core_site || exit 1

exit 0
