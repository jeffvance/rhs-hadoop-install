		RHS-Hadoop Installation Development

 
  NOTE: this files in this repo/directory are NOT meant to be run stand-alone.
  
  The rhs-hadoop-install repo has a dependency on the public glusterfs-hadoop-
  install community repo, and therefore this communiuty repo must be available
  in a known location before rhs-based tarballs can be created or direct
  installs can be performed.

  After cloning the rhs-hadoop-install repo, cd to the "rhs-hadoop-install" 
  directory and execute a script named FIRST_PREP_REPO.sh. This script clones
  the common glusterfs-hadoop-install repo if not present, or refreshes it if
  present. It also creates symbolic links to every common file contained in the
  glusterfs-hadoop-install repo.

  NOTE: After reading this README-DEV file the very next step is to run the
        FIRST_PREP_REPO.sh script!

  The files contained in rhs/ and in rhs/ sub-directories are automatically
  copied to 

  NOTE: this script is not meant to be run stand-alone. It is automatically
  invoked by the common prep_node.sh script found in the public community 
  glusterfs-hadoop-install repo. This repo must be cloned/pulled prior to
  building any RHS-specific tarballs. The community repo is linked to from the
  forge-gluster site (https://forge.gluster.org/).

  General packaging and generic install directions are found in the parent
  directory README file. This directory contains files, scripts, and sub-
  directories used to perform RHS-specific volume preparations that are not
  part of the common installation process.

  Currently, this includes:
  - ...
  - ...

  The community install.sh script sets up the hosts defined in the local "hosts"
  file as a trusted Glusterfs storage pool. The pre_install.sh script in the
  rhs/ directory is executed as one of the first steps of the common
  ../prep_node.sh script. Here, RHS-specific settings are configured to optimize
  RHS for Hadoop workloads. It is expected that the Red Hat Storage installation
  guide was followed to set up RHS. Note: the storage (brick) partition (e.g.
  /dev/sdb) should be configured as RAID 6.


== Sub-directories ==

  rhs2.1/ --
     - blah, blah
     - ...

  rhs2.0/ -- archive scripts and files
     - blah, blah
     - rhs2.0/: directory which may contain one or more of the following:
     - Ambari_Configuration_Guide.pdf
     - ambari-<version>.rpms.tar.gz: Ambari server and agent RPMs.
     - ambari.repo: Ambari's repo file.
     - fuse-patch.tar.gz: FUSE patch RPMs.
     - gluster-hadoop-<version>.jar: Gluster-Hadoop plug-in.
     - ktune.sh: optimized RHEL 2.0.5 tuned-adm high-throughput script
     - prep_node.sh: Ambari-specific install script (not to be executed
       directly).
 
  hdp2.x/ -- hdp 2.x scripts and files
     - a and b 
     - ...


==  Red Hat Network Registering (RHN) ==

  pre_install.sh will automatically register each node in the "hosts" file with
  the Red Hat Network (RHN) when the --rhn-user and --rhn-pass options are used.
  If the --rhn-* options are not specified, it is assumed that the servers have
  been manually registered prior to running pre_install.sh. If not, the 
  installation may fail.


== Installation ==

  - the correct version of RHS needs to be installed on each node per RHS
    guidelines. The RHS ISO just needs to be installed with a separate data
    (brick) partition and with static IP addresss configured. Do not create a
    gluster volume.
  - the data partition has been set up as RAID 6. It is usually created as
    /dev/sdb.
  - the order of the nodes in the "hosts" file is in replica order.
  - the --mgmt-node option is IGNORED for now.

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
    to be followed.  After hadoop distro installation completes, create gluster 
    base directories and fix permissions by running this script:
    
    $ ./post_install_dirs.sh /mnt/glusterfs /lib/hadoop
 
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
