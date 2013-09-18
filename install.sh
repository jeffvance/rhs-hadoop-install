#! /bin/bash
#
# Copyright (c) 2013 Red Hat, Inc.
# License: Apache License v2.0
# Author: Jeff Vance <jvance@redhat.com>
#
# This script (and the companion prep_node.sh script) helps to set up Gluster
# (RHS) for Hadoop workloads. It is expected that the Red Hat Storage 
# installation guide was followed to setup up RHS. The storage (brick) 
# partition should be configured as RAID 6. This script does not enforce any
# aspects of the RHS installation procedures.
#
# A tarball named "rhs-ambari-<version>.tar.gz" is downloaded to one of the
# cluster nodes (more common) or to the user's localhost (less common). The
# download location is arbitrary, though installing from the same node as will
# become the management node will reduce password-less ssh set up. Password-
# less ssh is needed from the node hosting the rhs install tarball to all nodes
# in the cluster. Password-less ssh is not necessary to and from all nodes
# within the cluster.
#
# The rhs tarball contains the following:
#  - install.sh: this script, executed by the root user
#  - README.txt: readme file to be read first
#  - hosts.example: sample "hosts" config file
#  - data/: directory containing:
#    - prep_node.sh: companion script, not to be executed directly
#    - gluster-hadoop-<version>.jar: Gluster-Hadoop plug-in
#    - fuse-patch.tar.gz: FUSE patch RPMs
#    - ambari.repo: repo file needed to install ambari
#    - ambari-<version>.rpms.tar.gz: Ambari server and agent RPMs
#
# install.sh is the main script and should be run as the root user. It installs
# the files in the data/ directory to each node contained in the "hosts" file.
#
# The "hosts" file must be created by the user. It is not part of the tarball
# but an example hosts file is provided. The "hosts" file is expected to be
# created in the same location where the tarball has been downloaded. If a
# different location is required the --hosts option can be used to specify the
# "hosts" file path. The "hosts" file contains a list of IP address and
# hostname pairs, one pair per line. Each line represents one node in the
# storage cluster (gluster trusted pool). Example:
#    ip-for-node-1 node-1
#    ip-for-node-3 node-3
#    ip-for-node-2 node-2
#    ip-for-node-4 node-4
#
# IMPORTANT: the node order in the hosts file is critical. Assuming the gluster
#   volume is created with replica 2 (which is the only config tested for RHS)
#   then each pair of lines in hosts represents replica pairs. For example, the
#   first 2 lines in hosts are replica pairs, as are the next two lines, etc.
# IMPORTANT: unless the --mgmt-node option is specified, the first host in the
#   hosts file is assumed to be the Ambari server node (and it is also a
#   storage node).
#
# Assumptions:
#  - passwordless SSH is setup between the installation node and each storage
#    node **
#  - correct version of RHS installed on each node per RHS guidelines
#  - a data partition has been created for the storage brick
#  - storage partition is setup as RAID 6
#  - the order of the nodes in the "hosts" file is in replica order
#  ** verified by this script
#
# See the usage() function for arguments and their definitions.

# set global variables
SCRIPT=$(/bin/basename $0)
INSTALL_VER='0.24'   # self version
INSTALL_DIR=$PWD     # name of deployment (install-from) dir
INSTALL_FROM_IP=$(hostname -i)
REMOTE_INSTALL_DIR="/tmp/RHS-Ambari-install/" # on each node
DATA_DIR='data/'     # subdir in rhs-ambari install dir
# companion install script name
PREP_SH="$REMOTE_INSTALL_DIR${DATA_DIR}prep_node.sh" # full path
NUMNODES=0           # number of nodes in hosts file (= trusted pool size)
bricks=''            # string list of node:/brick-mnts for volume create
# local logfile on each host, copied from remote host to install-from host
PREP_NODE_LOG='prep_node.log'
PREP_NODE_LOG_PATH="${REMOTE_INSTALL_DIR}$PREP_NODE_LOG"

# log threshold values
LOG_DEBUG=0
LOG_INFO=1    # default for --verbose
LOG_SUMMARY=2 # default
LOG_REPORT=3  # suppress all output, other than final reporting
LOG_QUIET=9   # value for --quiet = suppress all output
LOG_FORCE=99  # force write regardless of VERBOSE setting


# display: append the passed-in message to localhost's logfile, and potentially
# write the message to stdout, depending on the value of the passed-in priority
# setting.
# $1=msg, $2=msg prioriy (optional, default=summary)
#
function display(){  

  local pri=${2:-$LOG_SUMMARY}

  echo "$1" >> $LOGFILE
  (( pri >= VERBOSE )) && echo -e "$1"
}


# short_usage: write short usage to stdout.
#
function short_usage(){

  cat <<EOF

Syntax:

$SCRIPT [-v|--version] | [-h|--help]

$SCRIPT [--brick-mnt <path>] [--vol-name <name>] [--vol-mnt <path>]
           [--replica <num>]    [--hosts <path>]    [--mgmt-node <node>]
           [--rhn-user <name>]  [--rhn-pass <value>]
           [--logfile <path>]   [--verbose [num] ]
           [-q|--quiet]         [--debug]           [--old-deploy]
           brick-dev

EOF
}

# usage: write full usage/help text to stdout.
#
function usage(){

  cat <<EOF

Usage:

Deploys Hadoop on top of Red Hat Storage (RHS). Each node in the storage
cluster must be defined in the "hosts" file. The "hosts" file is not included
in the RHS tarball but must be created prior to running this script. The file
format is:
   hostname  host-ip-address
repeated one host per line in replica pair order. See the "hosts.example"
sample hosts file for more information.
  
The required brick-dev argument names the brick device where the XFS file
system will be mounted. Examples include: /dev/<VGname>/<LVname> or /dev/vdb1,
etc. The brick-dev names a storage partition dedicated for RHS. Optional
arguments can specify the RHS volume name and mount point, and the brick mount
point.
EOF
  short_usage
  cat <<EOF
  brick-dev          : (required) Brick device location/directory where the
                       XFS file system is created. Eg. /dev/vgName/lvName.
  --brick_mnt <path> : Brick directory. Default: "/mnt/brick1/<volname>".
  --vol-name  <name> : Gluster volume name. Default: "HadoopVol".
  --vol-mnt   <path> : Gluster mount point. Default: "/mnt/glusterfs".
  --replica   <num>  : Volume replication count. The number of storage nodes
                       must be a multiple of the replica count. Default: 2.
  --hosts     <path> : path to \"hosts\" file. This file contains a list of
                       "IP-addr hostname" pairs for each node in the cluster.
                       Default: "./hosts".
  --mgmt-node <node> : hostname of the node to be used as the management node.
                       Default: the first node appearing in the "hosts" file.
  --rhn-user  <name> : Red Hat Network user name. Default is to not register
                       the storage nodes.
  --rhn-pass <value> : RHN password for rhn-user. Default is to not register
                       the storage nodes.
  --logfile   <path> : logfile name. Default is "/var/log/RHS-install.log".
  --verbose   [=num] : set the verbosity level to a value of 0, 1, 2, 3. If
                       --verbose is omitted the default value is 2(summary). If
                       --verbose is supplied with no value verbosity is set to
                       1(info).  0=debug, 1=info, 2=summary, 3=report-only.
                       Note: all output is still written to the logfile.
  --debug            : maximum output. Internally sets verbose=0.
  -q|--quiet         : suppress all output including the final summary report.
                       Internally sets verbose=9. Note: all output is still
                       written to the logfile.
  --old-deploy       : Use if this is an existing deployment. The default
                       is a new ("greenfield") RHS customer installation. Not
                       currently supported.
  -v|--version       : current version string.
  -h|--help          : help text (this).

EOF
  
}

# parse_cmd: getopt used to do general parsing. The brick-dev arg is required.
# The remaining parms are optional. See usage function for syntax. Note: since
# the logfile path is an option, parsing errors may be written to the default
# logfile rather than the user-defined logfile, depending on when the error
#  occurs.
#
function parse_cmd(){

  local OPTIONS='vhq'
  local LONG_OPTS='brick-mnt:,vol-name:,vol-mnt:,replica:,hosts:,mgmt-node:,rhn-user:,rhn-pass:,logfile:,verbose::,old-deploy,help,version,quiet,debug'

  # defaults (global variables)
  BRICK_DIR='/mnt/brick1'
  VOLNAME='HadoopVol'
  GLUSTER_MNT='/mnt/glusterfs'
  REPLICA_CNT=2
  NEW_DEPLOY=true
  # "hosts" file concontains hostname ip-addr for all nodes in cluster
  HOSTS_FILE="$INSTALL_DIR/hosts"
  MGMT_NODE=''
  RHN_USER=''
  RHN_PASS=''
  LOGFILE='/var/log/RHS-install.log'
  VERBOSE=$LOG_SUMMARY

  local args=$(getopt -n "$SCRIPT" -o $OPTIONS --long $LONG_OPTS -- $@)
  (( $? == 0 )) || { echo "$SCRIPT syntax error"; exit -1; }

  eval set -- "$args" # set up $1... positional args
  while true ; do
      case "$1" in
	-h|--help)
	    usage; exit 0
	;;
	-v|--version)
	    echo "$SCRIPT version: $INSTALL_VER"; exit 0
	;;
	--brick-mnt)
	    BRICK_DIR=$2; shift 2; continue
	;;
	--vol-name)
	    VOLNAME=$2; shift 2; continue
	;;
	--vol-mnt)
	    GLUSTER_MNT=$2; shift 2; continue
	;;
	--replica)
	    REPLICA_CNT=$2; shift 2; continue
	;;
	--hosts)
	    HOSTS_FILE=$2; shift 2; continue
	;;
	--mgmt-node)
	    MGMT_NODE=$2; shift 2; continue
	;;
	--rhn-user)
	    RHN_USER=$2; shift 2; continue
	;;
	--rhn-pass)
	    RHN_PASS=$2; shift 2; continue
	;;
	--logfile)
	    LOGFILE=$2; shift 2; continue
	;;
	--verbose) # optional verbosity level
	    VERBOSE=$2 # may be "" if not supplied
            [[ -z "$VERBOSE" ]] && VERBOSE=$LOG_INFO # default
	    shift 2; continue
	;;
	-q|--quiet)
	    VERBOSE=$LOG_QUIET; shift; continue
	;;
	--debug)
	    VERBOSE=$LOG_DEBUG; shift; continue
	;;
	--old-deploy)
	    NEW_DEPLOY=false ;shift; continue
	;;
	--)  # no more args to parse
	    shift; break
	;;
	*) echo "Error: Unknown option: \"$1\""; exit -1
	;;
      esac
  done

  eval set -- "$@" # move arg pointer so $1 points to next arg past last opt

  # the brick dev is the only required parameter
  BRICK_DEV="$1"
  if [[ -z "$BRICK_DEV" ]] ; then
    echo "Syntax error: \"brick-dev\" is required"
    /bin/sleep 1
    short_usage
    exit -1
  fi

  # --rhn-user and --rhn-pass, validate potentially supplied options
  if [[ -n "$RHN_USER" ]] ; then
    if [[ -z "$RHN_PASS" ]] ; then 
      echo "Syntax error: rhn password required when rhn user specified"
      /bin/sleep 1
      short_usage
      exit -1
    fi
  fi

  # --logfile, if relative pathname make absolute
  # note: needed if scripts change cwd
  if [[ $(dirname "$LOGFILE") == '.' ]] ; then
    LOGFILE="$PWD/$LOGFILE"
  fi
}

# verify_local_deploy_setup: make sure the expected deploy files are in
# place. Collect all detected setup errors together (rather than one at a 
# time) for better usability. Validate format and size of hosts file.
# Verify connectivity between localhost and each data/storage node. Assign
# global HOSTS and HOST_IPS array variables and the MGMT_NODE variable.
#
function verify_local_deploy_setup(){

  local errmsg=''; local errcnt=0

  # read_verify_local_hosts_file: sub-function to read the deploy "hosts"
  # file, split it into the HOSTS and HOST_IPS global array variables, validate
  # hostnames and ips, and verify password-less ssh connectivity to each node.
  # Comments and empty lines are ignored in the hosts file. The number of nodes
  # represented in the hosts file is enforced to be a multiple of the replica
  # count.
  # 
  function read_verify_local_hosts_file(){

    local i; local host=''; local ip=''; local hosts_ary; local numTokens

    # regular expression to validate ip addresses
    local VALID_IP_RE='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'

    # regular expression to validate hostnames
    local VALID_HOSTNAME_RE='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'

    # read hosts file, skip comments and blank lines, parse out hostname and ip
    read -a hosts_ary <<< $(sed '/^ *#/d;/^ *$/d;s/#.*//' $HOSTS_FILE)
    numTokens=${#hosts_ary[@]}
    HOSTS=(); HOST_IPS=() # global vars

    # hosts file format: ip-address  hostname  # one pair per line
    for (( i=0; i<$numTokens; i++ )); do
	# IP address:
	ip=${hosts_ary[$i]}
	# validate basic ip-addr syntax
	if [[ ! $ip =~ $VALID_IP_RE ]] ; then
	  errmsg+=" * $HOSTS_FILE record $((i/2)):\n   Unexpected IP address syntax for \"$ip\"\n"
	  ((errcnt++))
	  break # exit loop
	fi
	HOST_IPS+=($ip)

	# hostname:
	((i++))
	host=${hosts_ary[$i]}
        # set MGMT_NODE to first node unless --mgmt-node specified
	if [[ -z "$MGMT_NODE" && $i == 1 ]] ; then # 1st hosts file record
	  MGMT_NODE="$host"
          MGMT_NODE_IN_POOL=true
	elif [[ -n "$MGMT_NODE" && "$MGMT_NODE" == "$host" ]] ; then
          MGMT_NODE_IN_POOL=true
        fi
	# validate basic hostname syntax
 	if [[ ! $host =~ $VALID_HOSTNAME_RE ]] ; then
	  errmsg+=" * $HOSTS_FILE record $((i/2)):\n   Unexpected hostname syntax for \"$host\"\n"
	  ((errcnt++))
	  break # exit loop
        fi
	HOSTS+=($host)

        # verify connectivity from localhost to data node. Note: ip used since
	# /etc/hosts may not be set up to map ip to hostname
	ssh -q -oBatchMode=yes root@$ip exit
        if (( $? != 0 )) ; then
	  errmsg+=" * $HOSTS_FILE record $((i/2)):\n   Cannot connect via password-less ssh to \"$host\"\n"
	  ((errcnt++))
	  break # exit loop
	fi
    done

    (( errcnt != 0 )) && return # errors in hosts checking loop are fatal

    # validate the number of nodes in the hosts file
    NUMNODES=${#HOSTS[@]}
    if (( NUMNODES < REPLICA_CNT )) ; then
      errmsg+=" * The $HOSTS_FILE file must contain at least $REPLICA_CNT nodes (replica count)\n"
      ((errcnt++))
    elif (( NUMNODES % REPLICA_CNT != 0 )) ; then
      errmsg+=" * The number of nodes in the $HOSTS_FILE file must be a multiple of the\n   replica count ($REPLICA_CNT)\n"
      ((errcnt++))
    fi
  }

  # main #
  if [[ ! -f $HOSTS_FILE ]] ; then
    errmsg+=" * \"$HOSTS_FILE\" file is missing.\n   This file contains a list of IP address followed by hostname, one\n   pair per line. Use \"hosts.example\" as an example.\n"
    ((errcnt++))
  else
    # read and verify/validate hosts file format
    read_verify_local_hosts_file
  fi
  if [[ ! -d $INSTALL_DIR/data ]] ; then
    errmsg+=" * \"$INSTALL_DIR/data\" sub-directory is missing.\n"
    ((errcnt++))
  fi

  if (( errcnt > 0 )) ; then
    local plural='s'
    (( errcnt == 1 )) && plural=''
    display "$errcnt error$plural:\n$errmsg" $LOG_FORCE
    exit 1
  fi
  display "   ...verified" $LOG_DEBUG
}

# report_deploy_values: write out args and default values to be used in this
# deploy/installation. Prompts to continue the script.
#
function report_deploy_values(){

  local ans='y'

  display
  display "__________ Deployment Values __________" $LOG_REPORT
  display "  Install-from dir:   $INSTALL_DIR"      $LOG_REPORT
  display "  Install-from IP:    $INSTALL_FROM_IP"  $LOG_REPORT
  display "  Remote install dir: $REMOTE_INSTALL_DIR"  $LOG_REPORT
  [[ -n "$RHN_USER" ]] && \
    display "  RHN user:           $RHN_USER"       $LOG_REPORT
  display "  \"hosts\" file:       $HOSTS_FILE"     $LOG_REPORT
  display "  Number of nodes:    $NUMNODES"         $LOG_REPORT
  display "  Management node:    $MGMT_NODE"        $LOG_REPORT
  display "  Volume name:        $VOLNAME"          $LOG_REPORT
  display "  Volume mount:       $GLUSTER_MNT"      $LOG_REPORT
  display "  # of replicas:      $REPLICA_CNT"      $LOG_REPORT
  display "  XFS device file:    $BRICK_DEV"        $LOG_REPORT
  display "  XFS brick dir:      $BRICK_DIR"        $LOG_REPORT
  display "  XFS brick mount:    $BRICK_MNT"        $LOG_REPORT
  display "  M/R scratch dir:    $MAPRED_SCRATCH_DIR"  $LOG_REPORT
  display "  New install:        $NEW_DEPLOY"       $LOG_REPORT
  display "  Verbose:            $VERBOSE"          $LOG_REPORT
  display "  Log file:           $LOGFILE"          $LOG_REPORT
  display    "_______________________________________" $LOG_REPORT

  (( VERBOSE < LOG_QUIET )) && read -p "Continue? [y|N] " ans
  case $ans in
    y|yes|Y|YES|Yes ) # ok, do nothing
    ;;
    * ) exit 0
  esac
}

# cleanup:
# 1) umount vol if mounted
# 2) stop vol if started **
# 3) delete vol if created **
# 4) detach nodes if trusted pool created
# 5) rm vol_mnt
# 6) unmount brick_mnt if xfs mounted
# 7) rm brick_mnt; rm mapred scratch dir
# ** gluster cmd only done once for entire pool; all other cmds executed on
#    each node
#
function cleanup(){

  local node=''; local out

  # 1) umount vol on every node, if mounted
  display "  -- un-mounting $GLUSTER_MNT on all nodes..." $LOG_INFO
  for node in "${HOSTS[@]}"; do
      out=$(ssh root@$node "
          if /bin/grep -qs $GLUSTER_MNT /proc/mounts ; then
            /bin/umount $GLUSTER_MNT
          fi")
      display "$node: $out" $LOG_DEBUG
  done

  # 2) stop vol on a single node, if started
  # 3) delete vol on a single node, if created
  display "  -- from node $firstNode:"         $LOG_INFO
  display "       stopping $VOLNAME volume..." $LOG_INFO
  display "       deleting $VOLNAME volume..." $LOG_INFO
  out=$(ssh root@$firstNode "
      gluster volume status $VOLNAME >& /dev/null
      if (( \$? == 0 )); then # assume volume started
        gluster --mode=script volume stop $VOLNAME 2>&1
      fi
      gluster volume info $VOLNAME >& /dev/null
      if (( \$? == 0 )); then # assume volume created
        gluster --mode=script volume delete $VOLNAME 2>&1
      fi
  ")
  display "$out" $LOG_DEBUG

  # 4) detach nodes if trusted pool created, on all but first node
  # note: peer probe hostname cannot be self node
  out=$(ssh root@$firstNode "gluster peer status|head -n 1")
  # detach nodes if a pool has been already been formed
  if [[ -n "$out" && ${out##* } > 0 ]] ; then # got output, last tok=# peers
    display "  -- from node $firstNode:" $LOG_INFO
    display "       detaching all other nodes from trusted pool..." $LOG_INFO
    out=''
    for (( i=1; i<$NUMNODES; i++ )); do
      out+=$(ssh root@$firstNode "gluster peer detach ${HOSTS[$i]} 2>&1")
      out+="\n"
    done
  fi
  display "$out" $LOG_DEBUG

  # 5) rm vol_mnt on every node
  # 6) unmount brick_mnt on every node, if xfs mounted
  # 7) rm brick_mnt and mapred scratch dir on every node
  display "  -- on all nodes:"          $LOG_INFO
  display "       rm $GLUSTER_MNT..."   $LOG_INFO
  display "       umount $BRICK_DIR..." $LOG_INFO
  display "       rm $BRICK_DIR and $MAPRED_SCRATCH_DIR..." $LOG_INFO
  out=''
  for node in "${HOSTS[@]}"; do
      out+=$(ssh root@$node "
          rm -rf $GLUSTER_MNT 2>&1
          if /bin/grep -qs $BRICK_DIR /proc/mounts ; then
            /bin/umount $BRICK_DIR 2>&1
          fi
          rm -rf $BRICK_DIR 2>&1
          rm -rf $MAPRED_SCRATCH_DIR 2>&1
      ")
      out+="\n"
  done
  display "$out" $LOG_DEBUG
}

# verify_pool_create: there are timing windows when using ssh and the gluster
# cli. This function returns once it has confirmed that the number of nodes in
# the trusted pool equals the expected number, or a predefined number of 
# attempts have been made.
#
function verify_pool_created(){

  local DESIRED_STATE="Peer in Cluster (Connected)"
  local out; local i=0; local LIMIT=10

  while (( i < LIMIT )) ; do # don't loop forever
      out=$(ssh root@$firstNode "gluster peer status|tail -n 1") # "State:"
      [[ -n "$out" && "${out#* }" == "$DESIRED_STATE" ]] && break
      sleep 1
     ((i++))
  done

  if (( i < LIMIT )) ; then 
    display "   Trusted pool formed..." $LOG_DEBUG
  else
    display "   FATAL ERROR: Trusted pool NOT formed..." $LOG_FORCE
    exit 5
  fi
}

# verify_vol_created: there are timing windows when using ssh and the gluster
# cli. This function returns once it has confirmed that $VOLNAME has been
# create, or a pre-defined number of attempts have been made.
#
function verify_vol_created(){

  local i=0; local LIMIT=10

  while (( i < LIMIT )) ; do # don't loop forever
      ssh root@$firstNode "gluster volume info $VOLNAME >& /dev/null"
      (( $? == 0 )) && break
      sleep 1
      ((i++))
  done

  if (( i < LIMIT )) ; then 
    display "   Volume \"$VOLNAME\" created..." $LOG_DEBUG
  else
    display "   FATAL ERROR: Volume \"$VOLNAME\" creation failed..." $LOG_FORCE
    exit 10
  fi
}

# verify_vol_started: there are timing windows when using ssh and the gluster
# cli. This function returns once it has confirmed that $VOLNAME has been
# started, or a pre-defined number of attempts have been made. A volume is
# considered started once all bricks are online.
#
function verify_vol_started(){

  local i=0; local LIMIT=10; local rtn
  local FILTER='^Online' # grep filter
  local ONLINE=': Y'     # grep not-match value

  while (( i < LIMIT )) ; do # don't loop forever
      # grep for Online status != Y
      rtn=$(ssh root@$firstNode "
	gluster volume status $VOLNAME detail 2>/dev/null |
	 	/bin/grep $FILTER |
		/bin/grep -v '$ONLINE' |
		wc -l
	")
      (( rtn == 0 )) && break # exit loop
      sleep 1
      ((i++))
  done

  if (( i < LIMIT )) ; then 
    display "   Volume \"$VOLNAME\" started..." $LOG_DEBUG
  else
    display "   FATAL ERROR: Volume \"$VOLNAME\" NOT started...\nTry gluster volume status $VOLNAME" $LOG_FORCE
    exit 15
  fi
}

# create_trusted_pool: create the trusted storage pool. No error if the pool
# already exists.
#
function create_trusted_pool(){

  local out; local i

  # note: peer probe hostname cannot be self node
  out=''
  for (( i=1; i<$NUMNODES; i++ )); do # starting at 1, not 0
      out+=$(ssh root@$firstNode "gluster peer probe ${HOSTS[$i]} 2>&1")
      out+="\n"
  done
  display "$out" $LOG_DEBUG

  out=$(ssh root@$firstNode 'gluster peer status 2>&1')
  display "$out" $LOG_DEBUG
}

# setup:
# 1) mkfs.xfs brick_dev
# 2) mkdir brick_dir; mkdir vol_mnt
# 3) append mount entries to fstab
# 4) mount brick
# 5) mkdir mapredlocal scratch dir (must be done after brick mount!)
# 6) create trusted pool
# 7) create vol **
# 8) start vol **
# 9) mount vol
# 10) create distributed mapred/system dir (done after vol mount)
# 11) chmod gluster mnt, mapred/system and brick1/mapred scratch dir
# 12) chown to mapred:hadoop the above
# ** gluster cmd only done once for entire pool; all other cmds executed on
#    each node
# TODO: limit disk space usage in MapReduce scratch dir so that it does not
#       consume too much of the shared storage space.
# NOTE: read comments below about the inablility to persist gluster volume
#       mounts via /etc/fstab when using pre-2.1 RHS.
#
function setup(){

  local i=0; local node=''; local ip=''; local out
  local PERMISSIONS='777' # for now until we learn how to reduce this...
  local OWNER='mapred'; local GROUP='hadoop'
  local BRICK_MNT_OPTS="noatime,inode64"
  local GLUSTER_MNT_OPTS="entry-timeout=0,attribute-timeout=0,_netdev"

  # 1) mkfs.xfs brick_dev on every node
  # 2) mkdir brick_dir and vol_mnt on every node
  # 3) append brick_dir and gluster mount entries to fstab on every node
  # 4) mount brick on every node
  # 5) mkdir mapredlocal scratch dir on every node (done after brick mount)
  display "  -- on all nodes:"                           $LOG_INFO
  display "       mkfs.xfs $BRICK_DEV..."                $LOG_INFO
  display "       mkdir $BRICK_DIR, $GLUSTER_MNT and $MAPRED_SCRATCH_DIR..." \
	$LOG_INFO
  display "       append mount entries to /etc/fstab..." $LOG_INFO
  display "       mount $BRICK_DIR..."                   $LOG_INFO
  out=''
  for (( i=0; i<$NUMNODES; i++ )); do
      node="${HOSTS[$i]}"
      ip="${HOST_IPS[$i]}"
      out+=$(ssh root@$node "
	/sbin/mkfs -t xfs -i size=512 -f $BRICK_DEV 2>&1
	/bin/mkdir -p $BRICK_MNT 2>&1 # volname dir under brick by convention
	/bin/mkdir -p $GLUSTER_MNT 2>&1
	# append brick and gluster mounts to fstab
	if ! /bin/grep -qs $BRICK_DIR /etc/fstab ; then
          echo '$BRICK_DEV $BRICK_DIR xfs  $BRICK_MNT_OPTS  0 0' >>/etc/fstab
	fi
	if ! /bin/grep -qs $GLUSTER_MNT /etc/fstab ; then
	  echo '$ip:/$VOLNAME  $GLUSTER_MNT  glusterfs  $GLUSTER_MNT_OPTS  0 0' >>/etc/fstab
	fi
	# Note: mapred scratch dir must be created *after* the brick is
	# mounted; otherwise, mapred dir will be "hidden" by the mount.
	# Also, permissions and owner must be set *after* the gluster dir 
	# is mounted for the same reason -- see below.
       	/bin/mount $BRICK_DIR 2>&1 # mount via fstab
       	/bin/mkdir -p $MAPRED_SCRATCH_DIR 2>&1
      ")
      out+="\n"
  done
  display "$out" $LOG_DEBUG

  # 6) create trusted pool from first node
  # 7) create vol on a single node
  # 8) start vol on a single node
  display "  -- from node $firstNode:"         $LOG_INFO
  display "       creating trusted pool..."    $LOG_INFO
  display "       creating $VOLNAME volume..." $LOG_INFO
  display "       starting $VOLNAME volume..." $LOG_INFO
  create_trusted_pool
  verify_pool_created

  # create vol
  out=$(ssh root@$firstNode "
	gluster volume create $VOLNAME replica $REPLICA_CNT $bricks 2>&1
  ")
  display "$out" $LOG_DEBUG
  verify_vol_created

  # start vol
  out=$(ssh root@$firstNode "
	gluster --mode=script volume start $VOLNAME 2>&1
  ")
  display "$out" $LOG_DEBUG
  verify_vol_started

  # 9) mount vol on every node
  # 10) create distributed mapred/system dir on every node
  # 11) chmod on the gluster mnt and the mapred scracth dir on every node
  # 12) chown on the gluster mnt and mapred scratch dir on every node
  display "  -- on all nodes:"                      $LOG_INFO
  display "       mount $GLUSTER_MNT..."            $LOG_INFO
  display "       create $MAPRED_SYSTEM_DIR dir..." $LOG_INFO
  display "       create $OWNER user and $GROUP group if needed..." $LOG_INFO
  display "       change owner and permissions..."  $LOG_INFO
  # Note: ownership and permissions must be set *afer* the gluster vol is
  #       mounted.
   #rhs pre-2.1 does not support the entry-timeout and attribute-timeout
   #options via shell mount command or via fstab. Thus, we run the gluserfs
   #command to do the gluster vol mount. However this method does NOT persist
   #the mount so whenever a data node reboots the gluster mount is lost! When
   #we support RHS 2.1+ then the 1st mount below can be uncommented and the
   #glusterfs mount below should be deleted.
  out=''
  for node in "${HOSTS[@]}"; do
      #can't mount via fstab in pre-RHS 2.1 releases...
      out+=$(ssh root@$node "
	 ##/bin/mount $GLUSTER_MNT # from fstab (UNCOMMENT this for rhs 2.1)
	 glusterfs --attribute-timeout=0 --entry-timeout=0 --volfile-id=/$VOLNAME --volfile-server=$node $GLUSTER_MNT 2>&1 # (DELETE this for rhs 2.1)

	 # create mapred/system dir
	 /bin/mkdir -p $MAPRED_SYSTEM_DIR 2>&1

	 # create mapred scratch dir and gluster mnt owner and group
       	 if ! /bin/grep -qsi \"^$GROUP\" /etc/group ; then
	   groupadd $GROUP 2>&1 # note: no password, no explicit GID!
       	 fi
       	 if ! /bin/grep -qsi \"^$OWNER\" /etc/passwd ; then
           # user added with no password and no hard-coded UID
           useradd --system -g $GROUP $OWNER 2>&1
       	 fi

	 /bin/chown -R $OWNER:$GROUP $GLUSTER_MNT $MAPRED_SCRATCH_DIR 2>&1
	 /bin/chmod $PERMISSIONS $GLUSTER_MNT $MAPRED_SCRATCH_DIR \
		    $MAPRED_SYSTEM_DIR 2>&1
	 /bin/chmod g+s $GLUSTER_MNT 2>&1 # set s-bit so subdirs inherit group
      ")
      out+="\n"
  done
  display "$out" $LOG_DEBUG
}

# install_nodes: for each node in the hosts file copy the "data" sub-directory
# and invoke the companion "prep" script. Some global variables are set here:
#   bricks               = string of all bricks (ip/dir)
#   DEFERRED_REBOOT_NODE = install-from hostname if install-from node needs
#     to be rebooted, else not defined
#   REBOOT_NODES         = array of IPs for all nodes needing to be rebooted,
#     except the install-from node which is handled by DEFERRED_REBOOT_NODE
#
# A node needs to be rebooted if the FUSE patch is installed. However, the node
# running the install script is not rebooted unless the users says yes.
# 
# Since the server(mgmt) node is known all other nodes are assumed to be 
# storage(agent) nodes. However the management node can also be a storage node.
# The right Ambari steps are performed depending on whether the target node is
# a management node, storage node, or both. 
#
function install_nodes(){

  local i; local node=''; local ip=''; local install_mgmt_node
  local LOCAL_PREP_LOG_DIR='/var/tmp/'; local out
  REBOOT_NODES=() # global

  # prep_node: sub-function which copies the data/ dir from the tarball to the
  # passed-in node. Then the prep_node.sh script is invoked on the passed-in
  # node to install these files. If prep.sh returns the "reboot-node" error
  # code and the node is not the "install-from" node then the global reboot-
  # needed variable is set. If an unexpected error code is returned then this
  # function exits.
  # Args: $1=hostname, $2=node's ip (can be hostname if ip is unknown),
  #       $3=flag to install storage node, $4=flag to install the mgmt node.
  #
  function prep_node(){

    local node="$1"; local ip="$2"; local install_storage="$3"
    local install_mgmt="$4"; local err

    # copy the data subdir to each node...
    # use ip rather than node for scp and ssh until /etc/hosts is set up
    ssh root@$ip "
	/bin/rm -rf $REMOTE_INSTALL_DIR
	/bin/mkdir -p $REMOTE_INSTALL_DIR"
    display "-- Copying RHS-Ambari install files..." $LOG_INFO
    out=$(script -q -c "scp -r $DATA_DIR root@$ip:$REMOTE_INSTALL_DIR")
    display "$out" $LOG_DEBUG

    # prep_node.sh may apply the FUSE patch on storage node in which case the
    # node will need to be rebooted.
    out=$(ssh root@$ip $PREP_SH $node $install_storage $install_mgmt \
	"\"${HOSTS[@]}\"" "\"${HOST_IPS[@]}\"" $MGMT_NODE $VERBOSE \
        $PREP_NODE_LOG_PATH $REMOTE_INSTALL_DIR$DATA_DIR "$RHN_USER" \
	"$RHN_PASS")
    err=$?
    # prep_node writes all messages to the PREP_NODE_LOG logfile regardless of
    # the verbose setting. However, it outputs (and is captured above) only
    # messages that honor the verbose setting. We can't call display() next
    # because we don't want to double log, so instead, append the entire
    # PREP_NODE_LOG file to LOGFILE and echo the contents of $out.
    scp -q root@$ip:$PREP_NODE_LOG_PATH $LOCAL_PREP_LOG_DIR
    cat ${LOCAL_PREP_LOG_DIR}$PREP_NODE_LOG >> $LOGFILE
    echo "$out" # prep_node.sh has honored the verbose setting

    if (( err == 99 )) ; then # this node needs to be rebooted
      # don't reboot if node is the install-from node!
      if [[ "$ip" == "$INSTALL_FROM_IP" ]] ; then
        DEFERRED_REBOOT_NODE="$node"
      else
	REBOOT_NODES+=("$ip")
      fi
    elif (( err != 0 )) ; then # fatal error in install.sh so quit now
      display " *** ERROR! prep_node script exited with error: $err ***" \
	$LOG_FORCE
      exit 20
    fi
  }

  ## main ##

  for (( i=0; i<$NUMNODES; i++ )); do
      node=${HOSTS[$i]}; ip=${HOST_IPS[$i]}
      echo
      display
      display '--------------------------------------------' $LOG_SUMMARY
      display "-- Installing on $node ($ip)"                 $LOG_SUMMARY
      display '--------------------------------------------' $LOG_SUMMARY
      display

      # Append to bricks string. Convention to use a subdir under the XFS
      # brick, and to name this subdir same as volname.
      bricks+=" $node:$BRICK_MNT"

      install_mgmt_node=false
      [[ -n "$MGMT_NODE_IN_POOL" && "$node" == "$MGMT_NODE" ]] && \
	install_mgmt_node=true
      prep_node $node $ip true $install_mgmt_node

      display '-------------------------------------------------' $LOG_SUMMARY
      display "-- Done installing on $node ($ip)"                 $LOG_SUMMARY
      display '-------------------------------------------------' $LOG_SUMMARY
  done

  # if the mgmt node is not in the storage pool (not in hosts file) then
  # we  need to copy the management rpm to the mgmt node and install the
  # management server
  if [[ -z "$MGMT_NODE_IN_POOL" ]] ; then
    echo
    display 'Management node is not a datanode thus mgmt code needs to be installed...' $LOG_INFO
    display "-- Starting install of management node \"$MGMT_NODE\"" $LOG_DEBUG
    prep_node $MGMT_NODE $MGMT_NODE false true
  fi
}

# reboot_nodes: if one or more nodes need to be rebooted, due to installing
# the FUSE patch, then they are rebooted here. Note: if the "install-from"
# node also needs to be rebooted that node is not in the REBOOT_NODES array
# and is handled separately (see the DEFERRED_REBOOT_NODE global variable).
#
function reboot_nodes(){

  local ip; local i; local msg; local num

  num=${#REBOOT_NODES[@]} # number of nodes to reboot
  if (( num > 0 )) ; then
    echo
    msg='node'
    (( num != 1 )) && msg+='s'
    display "-- $num $msg will be rebooted..." $LOG_SUMMARY
    for ip in "${REBOOT_NODES[@]}"; do
	display "   * rebooting node: $ip..." $LOG_INFO
	ssh root@$ip reboot -f &  # reboot asynchronously
    done

    # makes sure all rebooted nodes are back up before returning
    while true ; do
	for i in "${!REBOOT_NODES[@]}"; do # array of non-null element indices
	    ip=${REBOOT_NODES[$i]}         # unset leaves sparse array
	    # if possible to ssh to ip then unset that array entry
	    ssh -q -oBatchMode=yes root@$ip exit
	    if (( $? == 0 )) ; then
	      display "   * node $ip sucessfully rebooted" $LOG_DEBUG
	      unset REBOOT_NODES[$i] # null entry in array
	    fi
	done
	(( ${#REBOOT_NODES[@]} == 0 )) && break # exit loop
	sleep 10
    done
  fi
}

# perf_config: assign the non-default gluster volume attributes below.
#
function perf_config(){

  local out

  out=$(ssh root@$firstNode "
	gluster volume set $VOLNAME quick-read off 2>&1
	gluster volume set $VOLNAME cluster.eager-lock on 2>&1
	gluster volume set $VOLNAME performance.stat-prefetch off 2>&1
  ")
  display "$out" $LOG_DEBUG
}

# cleanup_logfile: the ambari-server yum install depends on Oracle JDK which
# is large and results in *many* progress updates. When written to disk this
# results in a *very* long record in the logfile and the user has to forward
# through hundreds of "pages" to get to the next useful record. So, this one
# very long record is deleted here.
#
function cleanup_logfile(){

  # yum install string for the ambari-server progress message
  local DELETE_STR='jdk-'

  sed -i "/$DELETE_STR/d" $LOGFILE
}

# reboot_self: invoked when the install-from node (self) is also one of the
# storage nodes. In this case the reboot of the storage node (needed to 
# complete the FUSE patch installation) has been deferred -- until now.
# The user is prompted to confirm the reboot of their node.
#
function reboot_self(){

  local ans=''

  echo "*** Your system ($(hostname -s)) needs to be rebooted to complete the"
  echo "    installation of the FUSE patch."
  read -p "    Reboot now? [y|N] " ans
  [[ "$ans" == 'Y' || "$ans" == 'y' ]] && reboot # bye!
  echo "No reboot! You must reboot your system prior to running Hadoop jobs."
}


## ** main ** ##
echo
parse_cmd $@

display "$(/bin/date). Begin: $SCRIPT -- version $INSTALL_VER ***" $LOG_REPORT

# define global variables based on --options and defaults
# convention is to use the volname as the subdir under the brick as the mnt
BRICK_MNT=$BRICK_DIR/$VOLNAME
MAPRED_SCRATCH_DIR="$BRICK_DIR/mapredlocal"    # xfs but not distributed
MAPRED_SYSTEM_DIR="$GLUSTER_MNT/mapred/system" # distributed, not local

echo
display "-- Verifying the deploy environment, including the \"hosts\" file format:" $LOG_INFO
verify_local_deploy_setup
firstNode=${HOSTS[0]}

report_deploy_values

# per-node install and config...
install_nodes

echo
display '----------------------------------------' $LOG_SUMMARY
display '--    Begin cluster configuration     --' $LOG_SUMMARY
display '----------------------------------------' $LOG_SUMMARY

# clean up mounts and volume from previous run, if any...
if [[ $NEW_DEPLOY == true ]] ; then
  echo
  display "-- Cleaning up (un-mounting, deleting volume, etc.)" $LOG_SUMMARY
  cleanup
fi

# set up mounts and create volume
echo
display "-- Setting up brick and volume mounts, creating and starting volume" \
	$LOG_SUMMARY
setup

echo
display "-- Performance config --" $LOG_SUMMARY
perf_config

cleanup_logfile

# reboot nodes where the FUSE patch was installed
reboot_nodes

echo
display "$(/bin/date). End: $SCRIPT" $LOG_REPORT
echo

# if install-from node is one of the data nodes and the fuse patch was
# installed on that data node, then the reboot of the node was deferred but
# can be done now.
[[ -n "$DEFERRED_REBOOT_NODE" ]] && reboot_self
exit 0
#
# end of script
