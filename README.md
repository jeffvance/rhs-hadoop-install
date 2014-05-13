		        RHS-Hadoop Installation

== Overview ==

  rhs-hadoop-install is a package that prepares Red Hat Storage (RHS, built on
  glusterfs) for Hadoop workloads. It is easy to install via yum and simple to
  execute via the main scripts found in /usr/share/rhs-hadoop-install.

  RHS sits on top of XFS, which is on top of LVM, which runs on RAID-6 disks.
  This environment is required of every data storage node in the cluster.  It is
  expected that all nodes in the storage cluster have RHS 3.0+ installed, and
  password-less SSH is necessary between the "deploy-from" node (where the main
  scripts run) to all nodes in the cluster.

  To install this package:
   - cd /usr/share,
   - yum install rhs-hadoop-install,

  To prepare RHS for Hadoop:
   - cd /usr/share/rhs-hadoop-install,
   - execute ./setup_cluster.sh
   - see /var/log/rhs-hadoop-install.log for install details.



== Instructions ==

 1) cd to /usr/share/rhs-hadoop-install

 2) execute "setup_cluster.sh":

    Output is displayed to STDOUT and is also written to a logfile. The default
    logfile is: /var/log/rhs-hadoop-install.log.

 3) When the script completes remaining hadoop distro and management steps need
    to be followed: 
      $ ./setup_container_executor.sh # per the directions provided to RHS 
                                      # customers
 
 4) Validate the installation per the directions provided to RHS customers. One
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

1) Installing Red Hat Storage

   The “Red Hat Storage 3.x Installation Guide” describes the prerequisites and
   provides step-by-instructions to install Red Hat Storage. The RHS 3.x
   Administration Guide should also be read.

   Additional RHS documentation, including release notes and installation 
   instructions are available here: 
     https://access.redhat.com/site/documentation/Red_Hat_Storage/. 

   Exceptions to the RHS 2.1 Installation Guide:

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

