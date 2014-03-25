		        RHS-Hadoop Installation

== Overview ==

  rhs-hadoop-install is a package that prepares Red Hat Storage (RHS, built on
  glusterfs) for Hadoop workloads. It is easy to install via yum and simple to
  execute via the install.sh script.

  RHS sits on top of XFS, which is on top of LVM, which runs on RAID-6 disks.
  This environment is required of every data storage node in the cluster, and
  ./install.sh will create the LVM PV, VG and LV as needed. It is expected that
  all nodes in the storage cluster have RHS 2.1.1 installed, and password-less
  SSH is necessary between the "deploy-from" node (where the install script is
  run) to all nodes in the cluster. There is a passwordless-ssh.sh script in
  the devutils/ directory to automate this if needed. Use the install.sh --help
  option to see the various install options available.

  To install this package:
   - cd /usr/share,
   - yum install rhs-hadoop-install,

  To prepare RHS for Hadoop:
   - cd /usr/share/rhs-hadoop-install,
   - create a local "hosts" file (see below),
   - execute ./install.sh [brick-dev],
   - see /var/log/rhs-hadoop-install.log for install details.


== Before you begin ==

  A local "hosts" file must be created before doing the install. It is not part
  of the rhs-hadoop-install package, but a sample hosts.example file is
  provided and should be read carefully. The "hosts" file defines the nodes 
  making up the storage cluster (trusted pool).

  The node order in the hosts file is critical. Assuming the storage volume is
  created with replica 2 then each pair of lines in "hosts" represents replica
  pairs. For example, the first 2 lines in hosts are replica pairs, as are the
  next two lines, etc.


== Instructions ==

 1) cd to /usr/share/rhs-hadoop-install

 2) create the local "hosts" file as described in hosts.example

 3) execute "install.sh":
    $ ./install.sh [options (see --help)] [brick-device]
    Example: ./install.sh /dev/sdb

    Output is displayed to STDOUT and is also written to a logfile. The default
    logfile is: /var/log/rhs-hadoop-install.log. Note: even when less verbose
    settings are used the logfile contains the greatest level of detail.

 4) When the script completes remaining hadoop distro and management steps need
    to be followed: 
      $ ./setup_container_executor.sh # per the directions provided to RHS 
                                      # customers
 
 5) Validate the installation per the directions provided to RHS customers. One
    example would be to:

    - Open a terminal and navigate to the Hadoop Directory
      cd /usr/lib/hadoop
     
    - Change user to the mapred user
      su mapred

    - Submit a TeraGen Hadoop job test
      bin/hadoop jar hadoop-examples-1.2.0.1.3.2.0-112.jar teragen 1000 in-dir
	
    - Submit a TeraSort Hadoop job test
      bin/hadoop jar hadoop-examples-1.2.0.1.3.2.0-112.jar terasort \
                 in-dir out-dir


== Addendum ==

1) Setting up password-less SSH 
 
   There is a utility script (devutils/passwordless-ssh.sh) which will set up
   password-less SSH from localhost (or wherever you run the script from) to 
   all hosts defined in the deploy "hosts" file. Use --help for more info.
 
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

