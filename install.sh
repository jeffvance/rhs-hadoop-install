#! /usr/bin/env bash
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
INSTALL_VER='0.11'   # self version
INSTALL_DIR=$(pwd)   # name of deployment (install-from) dir
INSTALL_FROM_IP=$(hostname -i)
REMOTE_INSTALL_DIR="/tmp/RHS-Ambari-install/" # on each node
DATA_DIR='data/'     # subdir in rhs-ambari install dir
# companion install script name
PREP_SH="$REMOTE_INSTALL_DIR${DATA_DIR}prep_node.sh" # full path
LOGFILE='/var/log/RHS-install.log'
NUMNODES=0           # number of nodes in hosts file (= trusted pool size)
bricks=''            # string list of node:/brick-mnts for volume create


# display: Write the message to stdlist and append it to localhost's logfile.
#
function display(){  # $1 is the message
  echo "$1" >> $LOGFILE
  echo -e "$1"
}

# short_usage: write short usage to stdout.
#
function short_usage(){

  echo -e "Syntax:\n"
  echo "$SCRIPT [-v|--version] | [-h|--help]"
  echo "$SCRIPT [--brick-mnt <path>] [--vol-name <name>] [--vol-mnt <path>]"
  echo "           [--replica <num>] [--hosts <path>] [--mgmt-node <node>]"
  echo "           [--rhn-user <name>] [--rhn-pw <value>] [--old-deploy]"
  echo "           brick-dev"
  echo
}

# usage: write full usage/help text to stdout.
#
function usage(){

  echo
  echo -e "$SCRIPT (version $INSTALL_VER)  Usage:\n"
  echo "Deploys Hadoop on top of Red Hat Storage (RHS). Each node in the storage"
  echo "cluster must be defined in the \"hosts\" file. The \"hosts\" file is not"
  echo "included in the RHS tarball but must be created prior to running this"
  echo "script. The file format is:"
  echo "      hostname  host-ip-address"
  echo "repeated one host per line in replica pair order. See the \"hosts.example\""
  echo "sample hosts file for more information."
  echo
  echo "The required brick-dev argument names the brick device where the XFS"
  echo "file system will be mounted. Examples include: /dev/<VGname>/<LVname>"
  echo "or /dev/vdb1, etc. The brick-dev names a storage partition dedicated"
  echo "for RHS. Optional arguments can specify the RHS volume name and mount"
  echo "point, and the brick mount point."
  echo
  short_usage
  echo "  brick-dev          : (required) Brick device location/directory where the"
  echo "                       XFS file system is created. Eg. /dev/vgName/lvName"
  echo "  --brick_mnt <path> : Brick directory. Default: \"/mnt/brick1/<volname>\""
  echo "  --vol-name  <name> : Gluster volume name. Default: \"HadoopVol\""
  echo "  --vol-mnt   <path> : Gluster mount point. Default: \"/mnt/glusterfs\""
  echo "  --replica   <num>  : Volume replication count. The number of storage nodes"
  echo "                       must be a multiple of the replica count. Default: 2"
  echo "  --hosts     <path> : path to \"hosts\" file. This file contains a list of"
  echo "                       \"IP-addr hostname\" pairs for each node in the cluster."
  echo "                       Default: \"./hosts\""
  echo "  --mgmt-node <node> : hostname of the node to be used as the management node."
  echo "                       Default: the first node appearing in the \"hosts\" file"
  echo "  --rhn-user  <name> : Red Hat Network user name. Default is to not register"
  echo "                       the storage nodes"
  echo "  --rhn-pw   <value> : RHN password for rhn-user. Default is to not register"
  echo "                       the storage nodes"
  echo "  --old-deploy       : Use if this is an existing deployment. The default"
  echo "                       is a new (\"greenfield\") RHS customer installation".
  echo "                       Not currently supported."
  echo "  -v|--version       : current version string"
  echo "  -h|--help          : help text (this)"
  echo
}

# parse_cmd: getopt used to do general parsing. The brick-dev arg is required.
# The remaining parms are optional. See usage function for syntax.
#
function parse_cmd(){

  local OPTIONS='vh'
  local LONG_OPTS='brick-mnt:,vol-name:,vol-mnt:,replica:,hosts:,mgmt-node:,rhn-user:,rhn-pw:,old-deploy,help,version'

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
  RHN_PW=''

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
	--rhn-pw)
	    RHN_PW=$2; shift 2; continue
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
  BRICK_DEV="$1"
  if [[ -z "$BRICK_DEV" ]] ; then
    echo "Syntax error: \"brick-dev\" is required"
    /bin/sleep 1
    short_usage
    exit -1
  fi
  if [[ -n "$RHN_USER" ]] ; then
    if [[ -z "$RHN_PW" ]] ; then 
      echo "Syntax error: rhn password required when rhn user specified"
      /bin/sleep 1
      short_usage
      exit -1
    fi
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

        # verify connectivity from localhost to data node
	# note: ip used since /etc/hosts may not be set up to map ip to hostname
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
  if [[ ! -e $HOSTS_FILE ]] ; then
    errmsg+=" * \"$HOSTS_FILE\" file is missing.\n   This file contains a list of storage hostnames followed by ip-address, one\n   pair per line.\n"
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
    display "$errcnt error$plural:\n$errmsg"
    exit 1
  fi
  display "   ...verified"
}

# report_deploy_values: write out args and default values to be used in this
# deploy/installation. Prompts to continue the script.
#
function report_deploy_values(){

  local ans

  echo
  display "__________ Deployment Values __________"
  display "  Install-from dir:   $INSTALL_DIR"
  display "  Install-from IP:    $INSTALL_FROM_IP"
  display "  Remote install dir: $REMOTE_INSTALL_DIR"
  [[ -n "$RHN_USER" ]] && \
    display "  RHN user:           $RHN_USER"
  display "  \"hosts\" file:       $HOSTS_FILE"
  display "  Number of nodes:    $NUMNODES"
  display "  Management node:    $MGMT_NODE"
  display "  Volume name:        $VOLNAME"
  display "  Volume mount:       $GLUSTER_MNT"
  display "  # of replicas:      $REPLICA_CNT"
  display "  XFS device file:    $BRICK_DEV"
  display "  XFS brick dir:      $BRICK_DIR"
  display "  XFS brick mount:    $BRICK_MNT"
  display "  M/R scratch dir:    $MAPRED_SCRATCH_DIR"
  display "  New install?:       $NEW_DEPLOY"
  display "  Log file:           $LOGFILE"
  echo    "_______________________________________"

  read -p "Continue? [y|N] " ans
  [[ "$ans" == 'Y' || "$ans" == 'y' ]] || exit 0
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
  display "  -- stopping ambari on all nodes..."
  display "  -- un-mounting $GLUSTER_MNT on all nodes..."
  for node in "${HOSTS[@]}"; do
      ssh root@$node "
          if /bin/grep -qs $GLUSTER_MNT /proc/mounts ; then
            /bin/umount $GLUSTER_MNT
          fi
      "
  done

  # 2) stop vol on a single node, if started
  # 3) delete vol on a single node, if created
  display "  -- from node $firstNode:"
  display "       stopping $VOLNAME volume..."
  display "       deleting $VOLNAME volume..."
  ssh root@$firstNode "
      gluster volume status $VOLNAME >& /dev/null
      if (( \$? == 0 )); then # assume volume started
        gluster --mode=script volume stop $VOLNAME
      fi
      gluster volume info $VOLNAME >& /dev/null
      if (( \$? == 0 )); then # assume volume created
        gluster --mode=script volume delete $VOLNAME
      fi
  "

  # 4) detach nodes if trusted pool created, on all but first node
  # note: peer probe hostname cannot be self node
  out=$(ssh root@$firstNode "gluster peer status|head -n 1")
  # detach nodes if a pool has been already been formed
  if [[ -n "$out" && ${out##* } > 0 ]] ; then # got output, last tok=# peers
    display "  -- from node $firstNode:"
    display "       detaching all other nodes from trusted pool..."
    for (( i=1; i<$NUMNODES; i++ )); do
        ssh root@$firstNode gluster peer detach ${HOSTS[$i]}
    done
  fi

  # 5) rm vol_mnt on every node
  # 6) unmount brick_mnt on every node, if xfs mounted
  # 7) rm brick_mnt and mapred scratch dir on every node
  display "  -- on all nodes:"
  display "       rm $GLUSTER_MNT..."
  display "       umount $BRICK_DIR..."
  display "       rm $BRICK_DIR and $MAPRED_SCRATCH_DIR..."
  for node in "${HOSTS[@]}"; do
      ssh root@$node "
          rm -rf $GLUSTER_MNT
          if /bin/grep -qs $BRICK_DIR /proc/mounts ; then
            /bin/umount $BRICK_DIR
          fi
          rm -rf $BRICK_DIR
          rm -rf $MAPRED_SCRATCH_DIR
      "
  done
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
    display "   Trusted pool formed..."
  else
    display "   FATAL ERROR: Trusted pool NOT formed..."
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
      ssh root@$firstNode "gluster volume info $VOLNAME"
      (( $? == 0 )) && break
      sleep 1
      ((i++))
  done

  if (( i < LIMIT )) ; then 
    display "   Volume \"$VOLNAME\" created..."
  else
    display "   FATAL ERROR: Volume \"$VOLNAME\" creation failed..."
    exit 10
  fi
}

# verify_vol_started: there are timing windows when using ssh and the gluster
# cli. This function returns once it has confirmed that $VOLNAME has been
# started, or a pre-defined number of attempts have been made. A volume is
# considered started once all bricks are online.
#
function verify_vol_started(){

  local i=0; local j; local LIMIT=10
  local FILTER="^Brick"    # grep filter
  local VOL_ONLINE_FIELD=5 # for cut -f
  local onlineBricks=()    # array of bricks, "Y" if brick is online

  while (( i < LIMIT )) ; do # don't loop forever
      # ensure all bricks are online
      read -a onlineBricks <<< $(ssh root@$firstNode "
	gluster volume status $VOLNAME 2>/dev/null | \
		grep $FILTER | \
		cut -f $VOL_ONLINE_FIELD")
      # all "Y" in onlineBricks means that all bricks are online
      for (( j=0; j<$NUMNODES; j++ )); do
	[[ ${onlineBricks[$j]} == 'Y' ]] || break
      done
      (( j == NUMNODES )) && break # all bricks online
      sleep 1
      ((i++))
  done

  if (( i < LIMIT )) ; then 
    display "   Volume \"$VOLNAME\" started..."
  else
    display "   FATAL ERROR: Volume \"$VOLNAME\" NOT started...\nTry gluster volume status $VOLNAME"
    exit 15
  fi
}

# create_trusted_pool: create the trusted storage pool. No error if the pool
# already exists.
#
function create_trusted_pool(){

  local out; local i

  # note: peer probe hostname cannot be self node
  for (( i=1; i<$NUMNODES; i++ )); do
      ssh root@$firstNode "gluster peer probe ${HOSTS[$i]}"
  done
  out=$(ssh root@$firstNode "gluster peer status")
  display "gluster peer status output:\n$out"
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

  local i=0; local node=''; local ip=''
  local PERMISSIONS='777'
  local OWNER='mapred'; local GROUP='hadoop'
  local BRICK_MNT_OPTS="noatime,inode64"
  local GLUSTER_MNT_OPTS="entry-timeout=0,attribute-timeout=0,_netdev"

  # 1) mkfs.xfs brick_dev on every node
  # 2) mkdir brick_dir and vol_mnt on every node
  # 3) append brick_dir and gluster mount entries to fstab on every node
  # 4) mount brick on every node
  # 5) mkdir mapredlocal scratch dir on every node (done after brick mount)
  display "  -- on all nodes:"
  display "       mkfs.xfs $BRICK_DEV..."
  display "       mkdir $BRICK_DIR, $GLUSTER_MNT and $MAPRED_SCRATCH_DIR..."
  display "       append mount entries to /etc/fstab..."
  display "       mount $BRICK_DIR..."
  for (( i=0; i<$NUMNODES; i++ )); do
      node="${HOSTS[$i]}"
      ip="${HOST_IPS[$i]}"
      ssh root@$node "
	 /sbin/mkfs -t xfs -i size=512 -f $BRICK_DEV
	 /bin/mkdir -p $BRICK_MNT # volname dir under brick by convention
	 /bin/mkdir -p $GLUSTER_MNT
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
       	 /bin/mount $BRICK_DIR # mount via fstab
       	 /bin/mkdir -p $MAPRED_SCRATCH_DIR
      "
  done

  # 6) create trusted pool from first node
  # 7) create vol on a single node
  # 8) start vol on a single node
  display "  -- from node $firstNode:"
  display "       creating trusted pool..."
  display "       creating $VOLNAME volume..."
  display "       starting $VOLNAME volume..."
  create_trusted_pool
  verify_pool_created
  # create vol
  ssh root@$firstNode "gluster volume create $VOLNAME replica $REPLICA_CNT $bricks 2>&1"
  verify_vol_created
  # start vol
  ssh root@$firstNode "gluster --mode=script volume start $VOLNAME 2>&1"
  verify_vol_started

  # 9) mount vol on every node
  # 10) create distributed mapred/system dir on every node
  # 11) chmod on the gluster mnt and the mapred scracth dir on every node
  # 12) chown on the gluster mnt and mapred scratch dir on every node
  display "  -- on all nodes:"
  display "       mount $GLUSTER_MNT..."
  display "       create $MAPRED_SYSTEM_DIR dir..."
  display "       create $OWNER user and $GROUP group if needed..."
  display "       change owner and permissions..."
  # Note: ownership and permissions must be set *afer* the gluster vol is
  #       mounted.
   #rhs pre-2.1 does not support the entry-timeout and attribute-timeout
   #options via shell mount command or via fstab. Thus, we run the gluserfs
   #command to do the gluster vol mount. However this method does NOT persist
   #the mount so whenever a data node reboots the gluster mount is lost! When
   #we support RHS 2.1+ then the 1st mount below can be uncommented and the
   #glusterfs mount below should be deleted.
  for node in "${HOSTS[@]}"; do
      #can't mount via fstab in pre-RHS 2.1 releases...
      ssh root@$node "
	 ##/bin/mount $GLUSTER_MNT # from fstab (UNCOMMENT this for rhs 2.1)
	 glusterfs --attribute-timeout=0 --entry-timeout=0 --volfile-id=/$VOLNAME --volfile-server=$node $GLUSTER_MNT # (DELETE this for rhs 2.1)

	 # create mapred/system dir
	 /bin/mkdir -p $MAPRED_SYSTEM_DIR

	 # create mapred scratch dir and gluster mnt owner and group
       	 if ! /bin/grep -qsi \"^$GROUP\" /etc/group ; then
	   groupadd $GROUP # note: no password, no explicit GID!
       	 fi
       	 if ! /bin/grep -qsi \"^$OWNER\" /etc/passwd ; then
           # user added with no password and no hard-coded UID
           useradd --system -g $GROUP $OWNER >&/dev/null
       	 fi

	 /bin/chmod $PERMISSIONS $GLUSTER_MNT $MAPRED_SCRATCH_DIR \
		    $MAPRED_SYSTEM_DIR
	 /bin/chown -R $OWNER:$GROUP $GLUSTER_MNT $MAPRED_SCRATCH_DIR
      "
  done
}

# install_nodes: for each node in the hosts file copy the "data" sub-directory
# and invoke the companion "prep" script. The global bricks variable is
# set here. A variable is set if the remote node is rebooted (eg. due to
# installing the FUSE patch).
#
function install_nodes(){

  aNodeRebooted=false # global
  local REBOOT_SLEEP_MINS=2m  # 2 minutes for a reboot
  local i; local node=''; local ip=''
  local install_mgmt_node

  # prep_node: sub-function which copies the data/ dir from the tarball to the
  # passed-in node. Then the prep_node.sh script is invoked on the passed-in
  # node to install these files. If prep.sh returns the "reboot-node" error
  # code and the node is not the "install-from" node then the global reboot-
  # needed variable is set. If an unexpected error code is returned then this
  # function exits.
  # Args: $1=hostname, $2=node's ip (can be hostname if no ip is known),
  #       $3=flag to install storage node, $4=flag to install the mgmt node.
  #
  function prep_node(){

    local node="$1"; local ip="$2"; local install_storage="$3"
    local install_mgmt="$4"; local err

    # copy the data subdir to each node...
    # use ip rather than node for scp and ssh until /etc/hosts is set up
    ssh root@$ip "rm -rf $REMOTE_INSTALL_DIR; /bin/mkdir -p $REMOTE_INSTALL_DIR"
    echo "-- Copying RHS-Ambari install files..."
    scp -rq $DATA_DIR root@$ip:$REMOTE_INSTALL_DIR

    # prep_node.sh may apply the FUSE patch on storage node in which case the
    # node needs to be rebooted.
    ssh root@$ip $PREP_SH $node $install_storage $install_mgmt \
	"\"${HOSTS[@]}\"" "\"${HOST_IPS[@]}\"" $MGMT_NODE \
	$REMOTE_INSTALL_DIR$DATA_DIR $LOGFILE "$RHN_USER" "$RHN_PW"
    err=$?

    if (( err == 99 )) ; then # this node needs to be rebooted
      # don't reboot if node is the install-from node!
      if [[ "$ip" == "$INSTALL_FROM_IP" ]] ; then
        DEFERRED_REBOOT_NODE="$node"
      else
        display "-- Starting reboot of $node now..."
        ssh root@$node reboot
        aNodeRebooted=true
      fi
    elif (( err != 0 )) ; then # fatal error in install.sh so quit now
      display " *** ERROR! prep_node script exited with error: $err ***"
      display " *** See logfile \"$LOGFILE\" on both \"$node\" and install host for details ***"
      exit 20
  fi
  }

  ## main ##

  for (( i=0; i<$NUMNODES; i++ )); do
      node=${HOSTS[$i]}; ip=${HOST_IPS[$i]}
      echo
      echo
      display "----------------------------------------"
      display "-- Deploying on $node ($ip)"
      display "----------------------------------------"
      echo

      # Append to bricks string.  Convention to use a subdir under the XFS
      #  brick, and to name this subdir same as volname.
      bricks+=" $node:$BRICK_MNT"

      install_mgmt_node=false
      [[ -n "$MGMT_NODE_IN_POOL" && "$node" == "$MGMT_NODE" ]] && \
	install_mgmt_node=true
#echo "******install_mgmt_node=$install_mgmt_node, MGMT_NODE_IN_POOL=$MGMT_NODE_IN_POOL, MGMT_NODE=$MGMT_NODE*****"
      prep_node $node $ip true $install_mgmt_node
  done

  # if the mgmt node is not in the storage pool (not in hosts file) then
  # we  need to copy the management rpm to the mgmt node and install the
  # management server
  if [[ -z "$MGMT_NODE_IN_POOL" ]] ; then
    echo
    display "-- Starting install of management node \"$MGMT_NODE\""
    prep_node $MGMT_NODE $MGMT_NODE false true
  fi

  # if we get here then there were no fatal errors in the companion install
  # script...
  # sleep a few mins if any node was rebooted
  if $aNodeRebooted ; then
    echo
    display "...sleeping ${REBOOT_SLEEP_MINS}inutes due to 1 or more nodes rebooting..."
    /bin/sleep $REBOOT_SLEEP_MINS
  fi
}

# perf_config: assign the non-default gluster volume attributes below.
#
function perf_config(){

  local out

  out=$(ssh root@$firstNode "gluster volume set $VOLNAME quick-read off; \
	gluster volume set $VOLNAME cluster.eager-lock on; \
	gluster volume set $VOLNAME performance.stat-prefetch off")

  display "Performance config output:\n$out"
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
  read -p "    Reboot now? [Y|N] " ans
  if [[ "$ans" == 'Y' || "$ans" == 'y' ]] ; then
    reboot
  else
    echo "No reboot! You must reboot your system prior to running Hadoop jobs."
  fi
}

## ** main ** ##

display "$(/bin/date). Begin: $SCRIPT -- version $INSTALL_VER ***"

parse_cmd $@

# convention is to use the volname as the subdir under the brick as the mnt
BRICK_MNT=$BRICK_DIR/$VOLNAME
MAPRED_SCRATCH_DIR="$BRICK_DIR/mapredlocal"    # xfs but not distributed
MAPRED_SYSTEM_DIR="$GLUSTER_MNT/mapred/system" # distributed, not local

echo
display "-- Verifying the deploy environment, including the \"hosts\" file format:"
verify_local_deploy_setup
firstNode=${HOSTS[0]}

report_deploy_values

# per-node install and config...
install_nodes

# clean up mounts and volume from previous run, if any...
if [[ $NEW_DEPLOY == true ]] ; then
  echo
  display "-- Cleaning up (un-mounting, deleting volume, etc.)"
  cleanup
fi

# set up mounts and create volume
echo
display "-- Setting up brick and volume mounts, creating and starting volume"
setup

echo
display "-- Performance config --"
perf_config

echo
display "$(/bin/date). End: $SCRIPT"
echo

# if install-from node is one of the data nodes and the fuse patch was
# installed on that data node, then the reboot of the node was deferred but
# can be done now.
[[ -n "$DEFERRED_REBOOT_NODE" ]] && reboot_self
exit 0
#
# end of script
