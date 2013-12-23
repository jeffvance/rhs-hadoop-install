		        RHS-Hadoop Installation

== Overview ==

  A tarball named rhs-hadoop-install-<version>.tar.gz has been extracted and now
  you're reading this file targetting end users (as opposed to the README-DEV
  readme file for install tool developers). The directory containing this readme
  file should also contain scripts (actually symbolic links) named install.sh,
  prep_node.sh, post_install_ dirs.sh, and should contain a sudoers file, a
  functions file, and the rhs/ directory.

  If you've already set up the local "hosts" file, and have password-less SSH
  between the install-from node and the install-to nodes working, then all you
  have left to do is to excute the ./install.sh script, providing the name of 
  the brick device.  Use the --help option to see what else is supported.

  If this is your first time then you'll need to create a local "hosts" file (as
  described below), establish password-less SSH from the install-from node (which
  is typically also the management node), and then run ./install.

  Note: it is expected that the Red Hat Storage installation guide was followed
    to set up RHS. The storage (brick) partition (e.g. /dev/sdb) should be
    configured as RAID 6.


== Before you begin ==

  The "hosts" file must be created by the root user doing the install. It is not
  part of the tarball, but an example hosts file is provided. The "hosts" file
  is expected to be created in the same directory where the tarball has been
  downloaded. If a different location is used then install.sh's "--hosts" option
  can be used to specify the "hosts" file path. The "hosts" file contains a list
  of IP adress followed by hostname (same format as /etc/hosts), one pair per
  line.  Each line represents one node in the storage cluster.
  Example:
     ip-for-node-1 hostname-for-node-1
     ip-for-node-3 hostname-for-node-3
     ip-for-node-2 hostname-for-node-2
     ip-for-node-4 hostname-for-node-4

  IMPORTANT: the node order in the hosts file is critical for two reasons:
  1) Assuming the storage volume is created with replica 2 then each pair of
     lines in hosts represents replica pairs. For example, the first 2 lines in
     hosts are replica pairs, as are the next two lines, etc.
  2) Hostnames are expected to be lower-case.

Note:
  - passwordless SSH is required between the installation node and each storage
    node. See the Addendum at the end of this document if you would like to see
    instructions on how to do this. There is a utility script in devutils/ named
    passwordless-ssh.sh which sets up password-less SSH using the nodes defined
    in the local hosts file.


==  Red Hat Network Registering (RHN) ==

  install.sh will automatically register each node in the "hosts" file with the
  Red Hat Network (RHN) when the --rhn-user and --rhn-pass options are used.  If
  the --rhn-* options are not specified, it is assumed that the servers have been
  manually registered prior to running pre_install.sh. If not, the installation
  may fail.


== Installation ==

  - the correct version of RHS needs to be installed on each node per RHS
    guidelines. The RHS ISO just needs to be installed with a separate data
    (brick) partition and with static IP addresss configured. Do not create a
    gluster volume.
  - the data partition has been set up as RAID 6. It is usually created as
    /dev/sdb.
  - the order of the nodes in the "hosts" file is in replica order.
  - the --mgmt-node option is IGNORED for now.


== Instructions ==

 0) upload rhs-hadoop-install-<version> tarball to the deployment directory on
    the "install-from" node.

 1) extract tarball to the local directory:
    $ tar xvzf rhs-hadoop-install-<version>.tar.gz

 2) cd to the extracted rhs-hadoop-install directory:
    $ cd rhs-hadoop-install-<version>

 3) create the "hosts" file per the instructions above.

 4) execute "install.sh" from the install directory:
    $ ./install.sh [options (see --help)] <brick-dev> (note: brick_dev is 
                                                       required)
    For example: ./install.sh -- rhn-user="me" --rhn-pass="pass" /dev/sdb

    Output is displayed on STDOUT and is also written to a logfile. The default
    logfile is: /var/log/rhs-hadoop-install.log. The --logfile option allows for
    a different logfile. Even when a less verbose setting is used the logfile
    will contain all messages.

 5) When the script completes remaining hadoop distro and management steps need
    to be followed. After the hadoop distro installation completes, create 
    gluster base directories and fix permissions by running this script:
    $ ./post_install_dirs.sh /mnt/glusterfs /lib/hadoop
 
 6) Validate the Installation:

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

   The “Red Hat Storage 2.1 Installation Guide” describes the prerequisites and
   provides step-by-instructions to install Red Hat Storage. The RHS 2.1
   Administration Guide should also be read.

   Additional RHS documentation, including release notes and installation 
   instructions are available here: 
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
