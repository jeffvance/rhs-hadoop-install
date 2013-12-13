		GlusterFS-Hadoop Packaging and Deployment

== Overview ==

  General packaging and generic install directions are found in the parent
  directory README file. This directory contains files and/or scripts used to 
  install fedora-specific aspects of the general installation process.

  The common ../install.sh script sets up the hosts defined in the local "hosts"
  file as a trusted Glusterfs storage pool. The pre_install.sh script in the
  fedora/ directory is executed as one of the first steps of the common
  ../prep_node.sh script. Here, fedroa-specific settings are configured to
  optimize fedora for Hadoop workloads.


== Installation ==
  
Instructions:
 0) upload the tarball to the deployment directory on the "install-from" node.

 1) extract tarball to the local directory:
    $ tar xvzf <tarballName-version.tar.gz>

 2) cd to the extracted rhs-hadoop-install directory:
    $ cd <tarballName-version>

 3) execute the common "install.sh" from the install directory:
    $ ./install.sh [options (see --help)] <brick-dev> (note: brick_dev is 
                                                       required)
    For example: ./install.sh /dev/sdb

    Output is displayed on STDOUT and is also written to a logfile. The default
    logfile is: /var/log/glusterfs-cluster-install.log. The --logfile option
    allows for a different logfile. Even when a less verbose setting is used
    the logfile will contain all messages.

 4) When the script completes remaining Hadoop distro and management steps need
    to be followed.  After hadoop distro installation completes, create gluster 
    base directories and fix permissions by running this common script:
    
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
