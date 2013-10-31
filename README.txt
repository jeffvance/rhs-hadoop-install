		RHS-Hadoop Installation Script 

== Overview ==

  The install.sh script (and the companion prep_node.sh script) sets up
  Red Hat Storage (RHS) for Hadoop workloads.  It is expected that the Red Hat
  Storage installation guide was followed to set up RHS. Note: the storage
  (brick) partition (e.g. /dev/sdb) should be configured as RAID 6.

  A tarball named "rhs-hadoop-install-<version>.tar.gz" is downloaded to one of
  the cluster nodes or to the user's localhost. The download directory is
  arbitrary. install.sh requires password-less ssh from the node hosting the
  rhs install tarball (the "install-from" node) to all nodes in the cluster.
  There is a utility script, devutils/passwordless-ssh.sh, to set up password-
  less SSH based on the nodes listed in the "hosts" file. 
 
  The rhs-hadoop-install tarball contains the following:
   - hosts.example: sample "hosts" config file.
   - install.sh: the main install script, executed by the root user.
   - prep_node.sh: companion script, not to be executed directly.
   - README.txt: this file.
   - rhs2.0/: directory containing:
     - Ambari_Configuration_Guide.pdf
     - ambari-<version>.rpms.tar.gz: Ambari server and agent RPMs.
     - ambari.repo: Ambari's repo file.
     - fuse-patch.tar.gz: FUSE patch RPMs.
     - gluster-hadoop-<version>.jar: Gluster-Hadoop plug-in.
     - ktune.sh: optimized RHEL 2.0.5 tuned-adm high-throughput script
     - prep_node.sh: Ambari-specific install script (not to be executed
       directly).
 
  install.sh is the main script and should be run as the root user. It installs
  the files in the rhs2.0/ directory to each node contained in the "hosts" file.
 
== Before you begin ==

  The "hosts" file must be created by the user doing the install. It is not
  part of the tarball, but an example hosts file is provided. The "hosts" file
  is expected to be created in the same directory where the tarball has been 
  downloaded. If a different location is required the "--hosts" option can be 
  used to specify the "hosts" file path. The "hosts" file contains a list of IP
  adress followed by hostname (same format as /etc/hosts), one pair per line.
  Each line represents one node in the storage cluster (gluster trusted pool).
  Example:
     ip-for-node-1 hostname-for-node-1
     ip-for-node-3 hostname-for-node-3
     ip-for-node-2 hostname-for-node-2
     ip-for-node-4 hostname-for-node-4
 
  IMPORTANT: the node order in the hosts file is critical for two reasons:
  1) Assuming the RHS volume is created with replica 2 (which is the only
     value supported for RHS) then each pair of lines in hosts represents
     replica pairs. For example, the first 2 lines in hosts are replica pairs,
     as are the next two lines, etc.
  2) Hostnames are expected to be lower-case.

  Red Hat Network Registering (RHN):
  ----------------------------------
  install.sh will automatically register each node in the "hosts" file with the
  Red Hat Network (RHN) when the --rhn-user and --rhn-pass options are used. 
  If the --rhn-* options are not specified, it is assumed that the servers have
  been manually registered prior to running install.sh. If not, the installation
  may fail.

  Note:
  - passwordless SSH is required between the installation node and each storage
    node. See the Addendum at the end of this document if you would like to see 
    instructions on how to do this. Note: there is a utility script named
    devutils/passwordless-ssh.sh which sets up password-less SSH using the nodes
    defined in the local hosts file.
  - the correct version of RHS needs to be installed on each node per RHS
    guidelines. The RHS ISO just needs to be installed with a separate data
    (brick) partition and with static IP addresss configured. Do not create a
    gluster volume.
  - the data partition has been set up as RAID 6. It is usually created as
    /dev/sdb.
  - the order of the nodes in the "hosts" file is in replica order.
  - the --mgmt-node option is IGNORED for now.

== Installation ==

Instructions:
 0) upload rhs-hadoop-install-<version> tarball to the deployment directory on
    the "install-from" node.

 1) extract tarball to the local directory:
    $ tar xvzf rhs-hadoop-install-<version>.tar.gz

 2) cd to the extracted rhs-hadoop-install directory:
    $ cd rhs-hadoop-install-<version>

 3) execute "install.sh" from the install directory:
    $ ./install.sh [options (see --help)] <brick-dev> (note: brick_dev is 
                                                       required)
    For example: ./install.sh -- rhn-user="me" --rhn-pass="pass" /dev/sdb

    Output is displayed on STDOUT and is also written to a logfile. The default
    logfile is: /var/log/RHS-install.log. The --logfile option allows for a
    different logfile. Even when a less verbose setting is used the logfile will
    contain all messages.

 4) When the script completes remaining Hadoop distro and management steps need
    to be followed.

 5) Validate the Installation

    Open a terminal and navigate to the Hadoop Directory
    cd /usr/lib/hadoop
     
    Change user to the mapred user
    su mapred

    Submit a TeraGen Hadoop job test
    bin/hadoop jar hadoop-examples-1.2.0.1.3.2.0-112.jar teragen 1000 in-dir
	
    Submit a TeraSort Hadoop job test
    bin/hadoop jar hadoop-examples-1.2.0.1.3.2.0-112.jar terasort in-dir out-dir


== Addendum ==

1) Setting up password-less SSH 
 
   There is a utility script (devutils/passwordless-ssh.sh) which will set up
   password-less SSH from localhost (or wherever you run the script from) to 
   all hosts defined in the local "hosts" file. Use --help for more info.
 
2) Installing Red Hat Storage

   The “Red Hat Storage 2.0 Installation Guide” describes the prerequisites and
   provides step-by-instructions to install Red Hat Storage. It is available in
   HTML (https://access.redhat.com/site/documentation/en-US/Red_Hat_Storage/2.0/html/Installation_Guide/index.html)  
   and is also available as a PDF.  

   The RHS 2.0 Administration Guide is available at: 
   https://access.redhat.com/site/documentation/en-US/Red_Hat_Storage/2.0/html/Installation_Guide/index.html 

   Additional RHS documentation, including release notes and installation instructions are available here: 
   https://access.redhat.com/site/documentation/Red_Hat_Storage/. 

   Exceptions to the RHS 2.0 Installation Guide:

     * 4.1.2 – set up static IP addresses, not DHCP.

     * 4.1.4 – chose a “custom layout” to create a dedicated storage partition.
               You want to have already set up a RAID 6 device for this
               partition.

   Exceptions to the RHS 2.0 Administration Guide:

     * skip all of section 7 -- don't create a trusted storage pool.

     * skip all of section 8 – don't create volumes.

     * the RHS-HDP installation configures volumes for optimal performance with
       Hadoop workloads.

     * the rest of the above guide can be read but not acted upon.
