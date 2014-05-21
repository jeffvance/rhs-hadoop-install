#!/bin/bash
#
# disable_vol.sh accepts a volume name and removes this volume from core-site
# on all relevant nodes.
#
# See usage() for syntax.

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

$ME [-y] [--user <ambari-admin-user>] [--pass <ambari-admin-password>] \\
           [--port <port-num>] [--hadoop-management-node <node>] \\
           [--rhs-node <node>] --yarn-master <node> <volname>
where:

  <volname> : the RHS volume to be disabled for hadoop workloads.
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

# edit_core_site: invoke bin/unset_glusterfs_uri to edit the core-site file and
# restart all ambari services across the cluster. Returns 1 on errors.
# Uses globals:
#   MGMT_*
#   PREFIX
#   VOLNAME
function edit_core_site() {

  local mgmt_node; local mgmt_u; local mgmt_p; local mgmt_port

  echo "Disable $VOLNAME in all core-site.xml files..."

  [[ -n "$MGMT_NODE" ]] && mgmt_node="-h $MGMT_NODE"
  [[ -n "$MGMT_USER" ]] && mgmt_u="-u $MGMT_USER"
  [[ -n "$MGMT_PASS" ]] && mgmt_p="-p $MGMT_PASS"
  [[ -n "$MGMT_PORT" ]] && mgmt_port="--port $MGMT_PORT"

  $PREFIX/bin/unset_glusterfs_uri.sh $mgmt_node $mgmt_u $mgmt_p $mgmt_port \
	$VOLNAME || return 1
}


## main ##

ME="$(basename $0 .sh)"
errcnt=0
AUTO_YES=0 # false

echo '***'
echo "*** $ME: version $(cat $PREFIX/VERSION)"
echo '***'

parse_cmd $@ || exit -1

if [[ -z "$MGMT_NODE" ]] ; then # omitted
  echo "No management node specified therefore the localhost ($HOSTNAME) is assumed"
  (( ! AUTO_YES )) && ! yesno  "  Continue? [y|N] " && exit -1
  MGMT_NODE="$HOSTNAME"
fi
if [[ -z "$RHS_NODE" ]] ; then # omitted
  echo "No RHS storage node specified therefore the localhost ($HOSTNAME) is assumed"
  (( ! AUTO_YES )) && ! yesno  "  Continue? [y|N] " && exit -1
  RHS_NODE="$HOSTNAME"
fi

vol_exists $VOLNAME $RHS_NODE || {
  echo "ERROR volume $VOLNAME does not exist";
  exit 1; }

NODES=($($PREFIX/bin/find_nodes.sh -n $RHS_NODE $VOLNAME)) # spanned by vol

echo
echo "*** NODES=${NODES[@]}"
echo

echo "$VOLNAME will be removed from all hadoop config files and thus will not be available for any hadoop workloads"
if (( AUTO_YES )) || yesno "  Continue? [y|N] " ; then
  edit_core_site || exit 1
fi

exit 0
