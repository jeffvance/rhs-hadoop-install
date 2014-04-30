#!/bin/bash
#
# setup_datanode.sh sets up this node's (localhost's) environment for hadoop
# workloads. Everything needed other than volume-specific tasks is done here.
# Syntax:
#  $1=block device path(s)
#  $2=brick mount path(s)
#  -q, if specified, means only set the exit code, do not output anything

errcnt=0; q=''

PREFIX="$(dirname $(readlink -f $0))"
[[ ${PREFIX##*/} != 'bin' ]] && PREFIX+='/bin'

# get_ambari_repo: wget the ambari repo file in the correct location.
function get_ambari_repo(){
 
  local REPO_DIR='/etc/yum.repos.d'
  local REPO_URL='http://public-repo-1.hortonworks.com/ambari/centos6/1.x/updates/1.4.4.23/ambari.repo'
  local out; local err; local errcnt=0

  [[ -d $REPO_DIR ]] || mkdir -p $REPO_DIR
  cd $REPO_DIR

  out="$(wget $REPO_URL 2>&1)"
  err=$?
  [[ -z "$QUIET" ]] && echo "wget ambari repo: $out"
  if (( err != 0 )) ; then
    [[ -z "$QUIET" ]] && echo "ERROR $err: ambari repo wget"
    ((errcnt++))
  fi

  cd - >/dev/null

  (( errcnt > 0 )) && return 1
  return 0
}

# setup_ambari_agent:
#
function setup_ambari_agent() {

}


## main ##

# parse cmd opts
while getopts ':q' opt; do
    case "$opt" in
      q)
        QUIET=true # else, undefined
        shift
        ;;
      \?) # invalid option
        shift # silently ignore opt
        ;;
    esac
done

BLKDEVS="$1"   # required, can be a list or a single value
BRICKMNTS="$2" # required, can be a list or a single value
[[ -n "$QUIET" ]] && q='-q'

setup_xfs          || ((errcnt++))
setup_ntp          || ((errcnt++))
setup_selinux      || ((errcnt++))
setup_iptables     || ((errcnt++))
setup_ambari_agent || ((errcnt++))
mount_blkdev       || ((errcnt++))

$PREFIX/add_users.sh $q  || ((errcnt++))
$PREFIX/add_groups.sh $q || ((errcnt++))
$PREFIX/add_dirs.sh $q   || ((errcnt++))

(( errcnt > 0 )) && exit 1
[[ -z "$QUIET" ]] && echo "${#VOL_SETTINGS[@]} volume settings successfully set"
exit 0
