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
           [--rhs-node <node>] --yarn-master <node> <volname>
where:

  <volname> : the RHS volume to be enabled for hadoop workloads.
  --yarn-master : hostname or ip of the yarn-master server which is expected to
      be outside of the storage pool.
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
  [[ -z "$YARN_NODE" ]] && {
    echo "Syntax error: the yarn-master node is required";
    ((errcnt++)); }

  (( errcnt > 0 )) && return 1
  return 0
}

# setup_nodes: setup each node for hadoop workloads by invoking
# bin/setup_datanodes.sh. Returns 1 on errors.
# Uses globals:
#   BLKDEVS
#   BRKMNTS
#   LOCALHOST
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

      [[ "$node" == "$LOCALHOST" ]] && { ssh=''; scp='#'; } || \
				       { ssh="ssh $node"; scp='scp'; }
      eval "$scp -r -q $PREFIX/bin $node:/tmp"
      eval "$ssh /tmp/bin/setup_datanode.sh --blkdev $blkdev \
		--brkmnt $brkmnt \
		--yarn-master $YARN_NODE \
		--hadoop-mgmt-node $MGMT_NODE"
      err=$?
      if (( err != 0 )) ; then
        echo "ERROR $err: setup_datanode failed on $node"
        errnodes+="$node "
        ((errcnt++))
      fi
      ((i++))
  done

  if (( errcnt > 0 )) ; then
    echo "$errcnt setup node errors on nodes: $errnodes"
    return 1
  fi

  return 0
}

# chk_and_fix_nodes: calls check_vol.sh to verify that VOLNAME has been setup
# for hadoop workloads, including each node spanned by the volume. If setup
# issues are detected then the user is optionally prompted to fix the problems.
# Returns 1 for errors.
# Uses globals:
#   AUTO_YES
#   PREFIX
#   RHS_NODE
#   VOLNAME
function chk_and_fix_nodes() {

  # verify that the volume is setup for hadoop workload and potentially fix
  if ! $PREFIX/bin/check_vol.sh -n $RHS_NODE $VOLNAME ; then # problems
    echo
    echo "One or more nodes spanned by $VOLNAME has issues"
    if (( AUTO_YES )) || yesno "  Correct above issues? [y|N] " ; then
      echo
      setup_nodes || return 1
      $PREFIX/bin/set_vol_perf.sh -n $RHS_NODE $VOLNAME || return 1
    else
      return 1
    fi
  fi

  return 0
}


## main ##

ME="$(basename $0 .sh)"
LOCALHOST="$(hostname)"
errcnt=0
AUTO_YES=0 # false

echo '***'
echo "*** $ME: version $(cat $PREFIX/VERSION)"
echo '***'

parse_cmd $@ || exit -1

if [[ -z "$MGMT_NODE" ]] ; then # omitted
  echo "No management node specified therefore the localhost ($LOCALHOST) is assumed"
  (( ! AUTO_YES )) && ! yesno  "  Continue? [y|N] " && exit -1
  MGMT_NODE="$LOCALHOST"
fi
if [[ -z "$RHS_NODE" ]] ; then # omitted
  echo "No RHS storage node specified therefore the localhost ($LOCALHOST) is assumed"
  (( ! AUTO_YES )) && ! yesno  "  Continue? [y|N] " && exit -1
  RHS_NODE="$LOCALHOST"
fi

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
echo "*** NODES=${NODES[@]}"
echo "*** BRKMNTS=${BRKMNTS[@]}"
echo "*** BLKDEVS=${BLKDEVS[@]}"
echo

if chk_and_fix_nodes ; then
  echo "Enable $VOLNAME in all core-site.xml files..."
  $PREFIX/bin/set_glusterfs_uri.sh -h $MGMT_NODE -u $MGMT_USER \
	-p $MGMT_PASS --port $MGMT_PORT $VOLNAME || exit 1
else
  exit 1
fi

exit 0
