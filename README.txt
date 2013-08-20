RHS-Ambari Installation Script v0.11

Description:
  The install.sh script (and the companion data/prep_node.sh script) sets up
  Red Hat Storage (RHS) for Hadoop workloads. It is expected that the Red Hat
  Storage installation guide was followed to set up RHS. The storage (brick)
  partition should be configured as RAID 6.
 
  A tarball named "rhs-ambari-install-<version>.tar.gz" is downloaded to one of
  the cluster nodes or to the user's localhost. The download directory is
  arbitrary. install.sh requires password-less ssh from the node hosting the
  rhs install tarball (the "install-from" node) to all nodes in the cluster. In
  addition, Ambari requires password-less ssh from the management node to all
  storage/agent nodes in the cluster. To simplify password-less ssh set up,
  the install-from node can be the same as the Ambari management node. The
  --mgmt-node option is available to specify the Ambari management node.
 
  The RHS tarball contains the following:
   - install.sh: this script, executed by the root user.
   - README.txt: this file.
   - hosts.example: sample "hosts" config file.
   - data/: directory containing:
     - prep_node.sh: companion script, not to be executed directly.
     - gluster-hadoop-<version>.jar: Gluster-Hadoop plug-in.
     - fuse-patch.tar.gz: FUSE patch RPMs.
     - ambari-<version>.rpms.tar.gz: Ambari server and agent RPMs.
     - ambari.repo: Ambari's repo file.
 
  install.sh is the main script and should be run as the root user. It installs
  the files in the data/ directory to each node contained in the "hosts" file.
 
  The "hosts" file must be created by the user. It is not part of the tarball
  but an example hosts file is provided. The "hosts" file is expected to be
  created in the same directory where the tarball has been downloaded. If a
  different location is required the "--hosts" option can be used to specify
  the "hosts" file path. The "hosts" file contains a list of IP adress followed
  by hostname (same format as /etc/hosts), one pair per line. Each line
  represents one node in the storage cluster (gluster trusted pool). Example:
     ip-for-node-1 hostname-for-node-1
     ip-for-node-3 hostname-for-node-3
     ip-for-node-2 hostname-for-node-2
     ip-for-node-4 hostname-for-node-4
 
  IMPORTANT: the node order in the hosts file is critical for two reasons:
  1) Assuming the RHS volume is created with replica 2 (which is the only
     configuration supported for RHS) then each pair of lines in hosts
     represents replica pairs. For example, the first 2 lines in hosts are
     replica pairs, as are the next two lines, etc.
  2) If the --mgmt-node option is not specified then the default management
     node is the *first* hostname listed in the "hosts" file. In this case the
     first node in the hosts file is both a storge node and the management
     node.

Red Hat Network Registering (RHN):
  install.sh will automatically register each node in the "hosts" file with the
  Red Hat Network (RHN) when the --rhn-user and --rhn-pw options are used. RHN
  registration is required for the Ambari installation. If the --rhn-* options
  are not specified no RHN registration is performed.


Assumptions:
  - passwordless SSH is setup between the installation node and each storage
    node **
  - the correct version of RHS has been installed on each node per RHS
    guidelines
  - a data partition has been created for the storage brick as RAID 6.
  - the order of the nodes in the "hosts" file is in replica order
  ** verified by the RHS installation scripts.

Instructions:
 0) upload rhs-ambari-install-<version> tarball to the deployment directory on
    the "install-from" node (most convenient if this is the Ambari management
    node, but this is not required)
 1) extract tarball to the local directory:
    $ tar xvzf rhs-ambari-install-<version>.tar.gz
 2) cd to the extracted rhs-ambari-install directory:
    $ cd rhs-ambari-install-<version>
 3) execute "install.sh" from the install directory:
    $ ./install.sh [options (see --help)] <brick-dev> (note: brick_dev is 
                                                       required)

 Output is displayed on STDOUT and is also written to /var/log/RHS-install on
 both the delpoyment node and on each data node in the cluster.
