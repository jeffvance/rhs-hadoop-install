RHS-Ambari Installation Script v0.4

Description:
  This script (and the companion data/prep_node.sh script) sets up Gluster
  (RHS) for Hadoop workloads. It is expected that the Red Hat Storage
  installation guide was followed to setup up RHS. The storage (brick)
  partition should be configured as RAID 6. This script does not enforce any
  aspects of the RHS installation procedures.
 
  A tarball named "rhs-ambari-install-<version>.tar.gz" is downloaded to one of
  the cluster nodes (more common) or to the user's localhost (less common). The
  download location is arbitrary. Password-less ssh is needed from the node
  hosting the rhs install tarball to all nodes in the cluster. RHS and Ambari
  do not require password-less ssh to and from all nodes within the cluster.
 
  The rhs tarball contains the following:
   - install.sh: this script, executed by the root user.
   - README.txt: this file.
   - hosts.example: sample "hosts" config file.
   - data/: directory containing:
     - prep_node.sh: companion script, not to be executed directly.
     - gluster-hadoop-<version>.jar: Gluster-Hadoop shim.
     - fuse-patch.tar.gz: FUSE patch RPMs.
     - ambari-<version>.rpms.tar.gz: Ambari server and agent RPMs.
     - ambari.repo: Ambari's repo file.
 
  install.sh is the main script and should be run as the root user. It installs
  the files in the data/ directory to each node contained in the "hosts" file.
 
  The "hosts" file must be created by the user. It is not part of the tarball
  but an example hosts file is provided. The "hosts" file is expected to be
  created in the same location where the tarball has been downloaded. If a
  different location is required the "--hosts" option can be used to specify
  the "hosts" file path. The "hosts" file contains a list of hostname and IP
  address pairs, one pair per line. Each line represents one node in the
  storage cluster (gluster trusted pool). Example:
     node-1  ip-for-node-1
     node-3  ip-for-node-3
     node-2  ip-for-node-2
     node-4  ip-for-node-4
 
  IMPORTANT: the node order in the hosts file is critical for two reasons:
  1) Assuming the gluster volume is created with replica 2 (which is the only
     configuration supported for RHS) then each pair of lines in hosts
     represents replica pairs. For example, the first 2 lines in hosts are
     replica pairs, as are the next two lines, etc.
  2) The *first* hostname is not only a storage node, it is also used as the
     management host/node. If possible, this host should be more powerful than
     the other storage nodes.

Assumptions:
  - passwordless SSH is setup between the installation node and each storage
    node **
  - correct version of RHS installed on each node per RHS guidelines
  - a data partition has been created for the storage brick as RAID 6.
  - the order of the nodes in the "hosts" file is in replica order
  ** verified by the RHS installation scripts.

Instructions:
 0) upload rhs-ambari-install-<version> tarball to the deployment directory,
    which can be a remote host or any of the storage nodes in the cluster.
 1) extract tarball to the local directory:
    $ tar xvzf rhs-ambari-install-<version>.tar.gz
 2) cd to the extracted rhs-ambari-install directory:
    $ cd rhs-ambari-install-<version>
 3) execute "install.sh" from the install directory:
    $ ./install.sh [options (see --help)] <brick-dev (required)>

 Output is displayed on STDOUT and also written to /var/log/RHS-install on both
 the delpoyment node and on each data node in the cluster.
