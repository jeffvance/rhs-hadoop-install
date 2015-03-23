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
            [--rhs-node <node>] [--yarn-master <node>] \\
            <volname>
where:

<volname>    : the RHS volume to be disabled for hadoop workloads.
--yarn-master: (optional) hostname or ip of the yarn-master server. Default is
               localhost.
--rhs-node   : (optional) hostname of any of the storage nodes. This is needed
               in order to access the gluster command. Default is localhost
               which, must have gluster cli access.
--hadoop-mgmt-node : (optional) hostname or ip of the hadoop mgmt server which
               is expected to be outside of the storage pool. Default is
               localhost.
-y           : (optional) auto answer "yes" to all prompts. Default is the
               script waits for the user to answer each prompt.
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

  # global defaults
  MGMT_PASS='admin'
  MGMT_PORT=8080
  MGMT_USER='admin'

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

# get_api_proto_and_port: sets global PROTO and PORT variables from the ambari
# configuration file. If they are missing then defaults are provided. Returns
# 1 for errors, else returns 0.
# Uses globals:
#   MGMT_NODE
#   PREFIX
# Sets globals:
#   PORT
#   PROTO
function get_api_proto_and_port() {

  local out; local ssh=''

  [[ "$MGMT_NODE" == "$HOSTNAME" ]] || ssh="ssh $MGMT_NODE"

  out="$(eval "$ssh $PREFIX/bin/find_proto_and_port.sh")"
  (( $? != 0 )) && {
    err "$out -- on $MGMT_NODE";
    return 1; }

  PROTO="${out% *}" # global
  PORT=${out#* }    # global
  return 0
}

# show_todo: display values set by the user and discovered by disable_vol.
# Uses globals:
#   CLUSTER_NAME
#   DEFAULT_VOL
#   MGMT_NODE
#   NEW_DFLT_VOL
#   NODES
#   PORT
#   PROTO
#   VOLMNT
#   VOLNAME
#   YARN_NODE
function show_todo() {

  local msg=''

  [[ "$DEFAULT_VOL" == "$VOLNAME" ]] && msg='(is the current default volume)'

  echo
  quiet "*** Volume             : $VOLNAME $msg"
  quiet "*** Current default vol: $DEFAULT_VOL"
  if [[ -z "$NEW_DFLT_VOL" ]] ; then
    quiet "*** New default volume : !!! there will be no enabled Hadoop volumes !!!"
  elif [[ "$DEFAULT_VOL" != "$NEW_DFLT_VOL" ]] ; then
    quiet "*** New default volume : $NEW_DFLT_VOL"
  fi
  quiet "*** Cluster name       : $CLUSTER_NAME"
  quiet "*** Nodes              : $(echo ${NODES[*]} | sed 's/ /, /g')"
  quiet "*** Ambari mgmt node   : $MGMT_NODE"
  quiet "***        proto/port  : $PROTO on port $PORT"
  quiet "*** Yarn-master server : $YARN_NODE"
  echo
}

# new_default_volume: sets the global NEW_DFLT_VOL variable to "" or to the
# name of the volume that will become the default volume if the user disables
# the target volume. After accounting for VOLNAME, the new default vol will be
# the first volume in the list of "fs.glusterfs.volumes" volumes.
# Uses globals:
#   CLUSTER_NAME
#   DEFAULT_VOL
#   MGMT_*
#   PREFIX
#   VOLNAME
# Sets globals:
#   NEW_DFLT_VOL
function new_default_volume() {

  local s # scratch string

  NEW_DFLT_VOL="$DEFAULT_VOL" # global

  if [[ "$DEFAULT_VOL" == "$VOLNAME" ]] ; then
    NEW_DFLT_VOL="$($PREFIX/bin/find_prop_value.sh fs.glusterfs.volumes core \
	$MGMT_NODE:$MGMT_PORT $MGMT_USER:$MGMT_PASS $CLUSTER_NAME)"
    (( $? != 0 )) && NEW_DFLT_VOL=''   # erase err msg if any

    # if we have the volume list then extract the new default volname
    if [[ -n "$NEW_DFLT_VOL" ]] ; then
      s=",$NEW_DFLT_VOL,"     # bracket with ","
      # remove VOLNAME from the list of vols	
      s="${s/,$VOLNAME,/,}"   # always a comma between volnames
      s="${s#,}"              # remove leading comma
      NEW_DFLT_VOL="${s%%,*}" # 1st volname from new list
    fi
  fi

  return 0
}

# edit_core_site: invoke bin/set_glusterfs_uri to edit the core-site file and
# restart all ambari services across the cluster. Returns 1 on errors.
# Uses globals:
#   CLUSTER_NAME
#   MGMT_*
#   PREFIX
#   VOLNAME
function edit_core_site() {

  local mgmt_u; local mgmt_p; local mgmt_port
  local err; local out

  verbose "--- disable $VOLNAME in all core-site.xml files..."

  [[ -n "$MGMT_USER" ]] && mgmt_u="-u $MGMT_USER"
  [[ -n "$MGMT_PASS" ]] && mgmt_p="-p $MGMT_PASS"
  [[ -n "$MGMT_PORT" ]] && mgmt_port="--port $MGMT_PORT"

  out="$($PREFIX/bin/set_glusterfs_uri.sh -h $MGMT_NODE $mgmt_u $mgmt_p \
	 $mgmt_port -c $CLUSTER_NAME --action remove $VOLNAME --debug)" 
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

# uniq nodes spanned by vol
NODES="$($PREFIX/bin/find_nodes.sh -un $RHS_NODE $VOLNAME)"
(( $? != 0 )) && {
  err "cannot find nodes spanned by $VOLNAME. $NODES";
  exit 1; }
debug "unique nodes spanned by $VOLNAME: ${NODES[*]}"

# check for passwordless ssh connectivity to all nodes
check_ssh $(uniq_nodes $MGMT_NODE $YARN_NODE $NODES) || exit 1

# get REST api protocol (http vs https) and port #
get_api_proto_and_port || exit 1
API_URL="$PROTO://$MGMT_NODE:$PORT"

CLUSTER_NAME="$($PREFIX/bin/find_cluster_name.sh $API_URL \
        $MGMT_USER:$MGMT_PASS)"
if (( $? != 0 )) || [[ -z "$CLUSTER_NAME" ]] ; then
  err "Cannot retrieve cluster name: $CLUSTER_NAME"
  exit 1
fi
debug "Cluster name: $CLUSTER_NAME"

DEFAULT_VOL="$($PREFIX/bin/find_default_vol.sh $API_URL \
	$MGMT_USER:$MGMT_PASS $CLUSTER_NAME)"
if (( $? != 0 )) || [[ -z "$DEFAULT_VOL" ]] ; then
  err "Cannot find any volumes in core-site config file. $DEFAULT_VOL"
  exit 1
fi
debug "Default volume: $DEFAULT_VOL"

# if the target vol is the default vol then get the new default vol
new_default_volume # sets global NEW_DLFT_VOL
debug "New default volume: $NEW_DFLT_VOL"

show_todo

msg="$VOLNAME"
[[ "$VOLNAME" == "$DEFAULT_VOL" ]] && msg+=', which is the DEFAULT volume,'
msg+=' will be removed from the core-site config file and thus will not be available for any Hadoop workloads. '
[[ -n "$NEW_DFLT_VOL" && "$NEW_DFLT_VOL" != "$DEFAULT_VOL" ]] &&
  msg+="The new default volume will be \"$NEW_DFLT_VOL\"."
force "$msg"
(( ! AUTO_YES )) && ! yesno "  Continue? [y|N] " && exit 0

if [[ -z "$NEW_DFLT_VOL" ]] ; then
  force "$VOLNAME is the *only* volume enabled for Hadoop jobs. Disabling it means that no Hadoop jobs can be run on this cluster."
  (( ! AUTO_YES )) && ! yesno "  Continue? [y|N] " && exit 0
fi

edit_core_site || exit 1
quiet "$VOLNAME disabled for hadoop workloads"

exit 0
