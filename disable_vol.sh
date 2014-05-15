#!/bin/bash
#
# disable_vol.sh accepts a volume name and removes this volume from core-site
# on all relevant nodes.
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

$ME disables an existing RHS volume from being used for hadoop
workloads.

SYNTAX:

$ME --version | --help

$ME [--user <ambari-admin-user>] [--pass <ambari-admin-password>] \\
            [--port <port-num>] [-y] \\
            --hadoop-management-node <node> --yarn-master <node> <volname>
where:

  <volname> : the RHS volume to be disabled.
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


## main ##

ME="$(basename $0 .sh)"
errcnt=0
AUTO_YES=0 # false

echo '***'
echo "*** $ME: version $(cat $PREFIX/VERSION)"
echo '***'

parse_cmd $@ || exit -1

NODES=($($PREFIX/bin/find_nodes.sh $VOLNAME)) # array
FIRST_NODE=${NODES[0]} # use this storage node for all gluster cli cmds

echo
echo "*** NODES=${NODES[@]}"
echo

# make sure the volume exists
vol_exists $VOLNAME $FIRST_NODE || exit 1

echo "$VOLNAME will be removed from all hadoop config files and thus will not be available for any hadoop workloads"
if (( AUTO_YES )) || yesno "  Continue? [y|N] " ; then
  echo "Disabling $VOLNAME in all core-site.xml files..."
  $PREFIX/bin/unset_glusterfs_uri.sh -h $MGMT_NODE -u $MGMT_USER \
	-p $MGMT_PASS --port $MGMT_PORT $VOLNAME || exit 1
fi

exit 0
