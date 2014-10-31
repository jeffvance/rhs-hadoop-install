#!/bin/bash
#
# disable_vol.sh accepts a volume name and removes this volume from the Hadoop
# core-site file's "fs.glusterfs.volumes" property value.
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

$ME [-y] [--quiet | --verbose | --debug] \\
            [--user <ambari-admin-user>] [--pass <ambari-admin-password>] \\
            [--port <port-num>] [--hadoop-mgmt-node <node>] \\
            [--rhs-node <node>] --yarn-master <node> \\
            <volname>
where:

<volname>    : the RHS volume to be disabled for hadoop workloads.
--yarn-master: hostname or ip of the yarn-master server which is expected to
               be outside of the storage pool.
--rhs-node   : (optional) hostname of any of the storage nodes. This is needed
               in order to access the gluster command. Default is localhost
               which, must have gluster cli access.
--hadoop-mgmt-node : (optional) hostname or ip of the hadoop mgmt server which
               is expected to be outside of the storage pool. Default is
               localhost.
-y : auto answer "yes" to all prompts. Default is to be promoted before the
               script continues.
--quiet      : (optional) output only basic progress/step messages. Default.
--verbose    : (optional) output --quiet plus more details of each step.
--debug      : (optional) output --verbose plus greater details useful for
               debugging.
--user       : the ambari admin user name. Default: "admin".
--pass       : the password for --user. Default: "admin".
--port       : the port number used by the ambari server. Default: 8080.
--version    : output only the version string.
--help       : this text.

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
#   VERBOSE
#   VOLNAME
#   YARN_NODE
function parse_cmd() {

  local opts='y'
  local long_opts='version,help,yarn-master:,rhs-node:,hadoop-mgmt-node:,user:,pass:,port:,verbose,quiet,debug'
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

  local mgmt_node; local mgmt_u; local mgmt_p; local mgmt_port
  local err; local out

  verbose "--- disable $VOLNAME in all core-site.xml files..."

  [[ -n "$MGMT_NODE" ]] && mgmt_node="-h $MGMT_NODE"
  [[ -n "$MGMT_USER" ]] && mgmt_u="-u $MGMT_USER"
  [[ -n "$MGMT_PASS" ]] && mgmt_p="-p $MGMT_PASS"
  [[ -n "$MGMT_PORT" ]] && mgmt_port="--port $MGMT_PORT"

  out="$($PREFIX/bin/set_glusterfs_uri.sh $mgmt_node $mgmt_u $mgmt_p \
	$mgmt_port --action remove $VOLNAME --debug)" 
  err=$?
  if (( err != 0 )) ; then
    err -e $err "unset_glusterfs_uri:\n$out"
    return 1
  fi
  debug -e "unset_glusterfs_uri:\n$out"

  verbose "--- disabled $VOLNAME"
  return 0
}


## main ##

ME="$(basename $0 .sh)"
AUTO_YES=0 # false
VERBOSE=$LOG_QUIET # default

report_version $ME $PREFIX

parse_cmd $@ || exit -1

default_nodes MGMT_NODE 'management' YARN_NODE 'yarn-master' \
        RHS_NODE 'RHS storage' || exit -1

# check for passwordless ssh connectivity to rhs_node first
check_ssh $RHS_NODE || exit 1

vol_exists $VOLNAME $RHS_NODE || {
  err "volume $VOLNAME does not exist";
  exit 1; }

NODES=($($PREFIX/bin/find_nodes.sh -n $RHS_NODE $VOLNAME)) # spanned by vol
if (( $? != 0 )) ; then
  err "${NODE[*]}" # error msg from find_nodes
  exit 1
fi
debug "nodes spanned by $VOLNAME: ${NODES[*]}"

# check for passwordless ssh connectivity to all nodes
check_ssh $(uniq_nodes $MGMT_NODE $YARN_NODE $NODES) || exit 1

DEFAULT_VOL="$($PREFIX/bin/find_default_vol.sh -n $RHS_NODE)"
debug "Default volume: $DEFAULT_VOL"

echo
quiet "*** Volume            : $VOLNAME"
quiet "*** Default volume    : $DEFAULT_VOL"
quiet "*** Nodes             : $(echo ${NODES[*]} | sed 's/ /, /g')"
quiet "*** Ambari mgmt node  : $MGMT_NODE"
quiet "*** Yarn-master server: $YARN_NODE"
echo

msg=''
[[ "$VOLNAME" == "$DEFAULT_VOL" ]] && msg=', which is the DEFAULT volume,'

force -e "$VOLNAME$msg will be removed from the core-site config file and thus\n  will not be available for any hadoop workloads."
if (( AUTO_YES )) || yesno "  Continue? [y|N] " ; then
  edit_core_site || exit 1
fi

quiet "$VOLNAME disabled for hadoop workloads"
exit 0
