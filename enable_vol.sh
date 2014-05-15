#!/bin/bash
#
# enable_vol.sh accepts a volume name, discovers and checks the volume mount on
# each node spanned by the volume to be sure they are setup for hadoop workloads,
# and then updates the core-site file to contain the volume. 
#
# See usage() for syntax.
#
# Assumption: script must be executed from a node that has access to the 
#  gluster cli.

PREFIX="$(dirname $(readlink -f $0))"

## functions ##

source $PREFIX/bin/functions

# usage: output the general description and syntax.
function usage() {

  cat <<EOF

$ME enables an existing RHS volume for hadoop workloads.

SYNTAX:

$ME --version | --help

$ME [--user <ambari-admin-user>] [--pass <ambari-admin-password>] \\
           [--port <port-num>] [-y] \\
           --hadoop-management-node <node> --yarn-master <node> <volname>
where:

  <volname> : the RHS volume to be enabled for hadoop workloads.
  --yarn-master : hostname or ip of the yarn-master server which is expected to
      be outside of the storage pool.
  --hadoop-mgmt-node : hostname or ip of the hadoop mgmt server which is expected
      to be outside of the storage pool.
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
#   VOLNAME
#   YARN_NODE
function parse_cmd() {

  local opts='y'
  local long_opts='version,help,yarn-master:,hadoop-mgmt-node:,user:,pass:,port:'
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
  [[ -z "$YARN_NODE" || -z "$MGMT_NODE" ]] && {
    echo "Syntax error: both yarn-master and hadoop-mgmt-node are required";
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
#   VOLNAME
function chk_and_fix_nodes() {

  # verify that the volume is setup for hadoop workload and potentially fix
  if ! $PREFIX/bin/check_vol.sh $VOLNAME ; then # 1 or more problems
    echo
    echo "One or more nodes spanned by $VOLNAME has issues"
    if (( AUTO_YES )) || yesno "  Correct above issues? [y|N] " ; then
      echo
      setup_nodes || return 1
      $PREFIX/bin/set_vol_perf.sh $VOLNAME || return 1
    else
      return 1
    fi
  fi

  return 0
}


## main ##

ME="$(basename $0 .sh)"
LOCALHOST=$(hostname)
errcnt=0
AUTO_YES=0 # false

echo '***'
echo "*** $ME: version $(cat $PREFIX/VERSION)"
echo '***'

parse_cmd $@ || exit -1

NODES=($($PREFIX/bin/find_nodes.sh $VOLNAME)) # arrays
FIRST_NODE=${NODES[0]} # use this storage node for all gluster cli cmds

BRKMNTS=($($PREFIX/bin/find_brick_mnts.sh -n $VOLNAME))
BLKDEVS=($($PREFIX/bin/find_blocks.sh -n $VOLNAME))

echo
echo "*** NODES=${NODES[@]}"
echo "*** BRKMNTS=${BRKMNTS[@]}"
echo "*** BLKDEVS=${BLKDEVS[@]}"
echo

# make sure the volume exists
vol_exists $VOLNAME $FIRST_NODE || exit 1

if chk_and_fix_nodes ; then
  echo "Enable $VOLNAME in all core-site.xml files..."
  $PREFIX/bin/set_glusterfs_uri.sh -h $MGMT_NODE -u $MGMT_USER \
	-p $MGMT_PASS --port $MGMT_PORT $VOLNAME || exit 1
else
  exit 1
fi

exit 0
