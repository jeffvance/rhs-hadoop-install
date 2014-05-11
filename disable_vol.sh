#!/bin/bash
#
# disable_vol.sh accepts a volume name and removes this volume from core-site
# on all relevant nodes.
#
# Syntax:
#  $1=volName: gluster volume name
#  -y: auto answer "yes" to any prompts
#  --yarn-master: hostname or ip of the yarn-master server (required)
#  --hadoop-mgmt-node: hostname or ip of the hadoop mgmt server (required)
#  --user: ambari admin user name
#  --pass: ambari admin user password
#  --port: ambari port
#
# Assumption: script must be executed from a node that has access to the 
#  gluster cli.

PREFIX="$(dirname $(readlink -f $0))"

## functions ##

source $PREFIX/bin/yesno

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
  local long_opts='yarn-master:,hadoop-mgmt-node:,user:,pass:,port:'
  local errcnt=0

  eval set -- "$(getopt -o $opts --long $long_opts -- $@)"

  while true; do
      case "$1" in
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

# vol_exists: invokes gluster vol info to see if VOLNAME exists. Returns 1 on
# errors.
# Uses globals:
#   VOLNAME
function vol_exists() {

  local err

  gluster volume info $VOLNAME >& /dev/null
  err=$?
  if (( err != 0 )) ; then
    echo "ERROR $err: vol info error on \"$VOLNAME\", volume may not exist"
    return 1
  fi

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

echo
echo "*** NODES=${NODES[@]}"
echo

# make sure the volume exists
vol_exists || exit 1

echo "$VOLNAME will be removed from all hadoop config files and thus will not be available for any hadoop workloads"
if (( AUTO_YES )) || yesno "  Continue? [y|N] " ; then
  echo "Disabling $VOLNAME in all core-site.xml files..."
  $PREFIX/bin/unset_glusterfs_uri.sh -h $MGMT_NODE -u $MGMT_USER \
	-p $MGMT_PASS -port $MGMT_PORT $VOLNAME || exit 1
fi

exit 0
