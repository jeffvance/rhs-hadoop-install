		        RHS-Hadoop Installation

== Overview ==

  rhs-hadoop-install is a package that prepares Red Hat Storage (RHS, built on
  glusterfs) for Hadoop workloads. It is easy to install via yum and simple to
  execute via the main scripts found in /usr/share/rhs-hadoop-install.

  RHS sits on top of XFS, which is on top of LVM, which runs on RAID-6 disks.
  This environment is required of every data storage node in the cluster. It is
  expected that all nodes in the storage cluster have RHS 3.0+ installed, and
  password-less SSH is necessary between the "deploy-from" node (from which the
  main scripts are run) to all nodes in the cluster.

  The recommended topology for a big data RHS cluster is one RHEL 6.5 Ambari
  management server, 1 (different) RHEL 6.5 Yarn-master server, and N (as a
  multiple of 2) RHS 3.0 storage nodes. It is possible to combine the Yarn node
  and the Ambari node, or even for these servers to be storage nodes, but this
  configuration is not recommended.

  To install this package:
   - cd /usr/share,
   - yum install rhs-hadoop-install,

  To prepare RHS for Hadoop:
   - cd /usr/share/rhs-hadoop-install,
   - execute ./setup_cluster.sh --yarn-master <node> --hadoop-mgmt-node <node> \
               <node1>:<brick-mnt>:<brick-dev> \
               <node2>[:<brick-mnt>][:<brick-dev>] ...
   - execute ./create_vol.sh <newVolName> <vol-mount> \
               <node1>:<brick-mnt> <node2>[:<brick-mnt>] ...
   - execute ./enable_vol.sh --yarn-master <node> --rhs-node <node> <volName>
   - see /var/log/rhs-hadoop-install.log for install details.


== Instructions ==

 1) cd to /usr/share/rhs-hadoop-install

 2) execute "setup_cluster.sh":

    Output is displayed to STDOUT and is also written to a logfile. The logfile
    is: /var/log/rhs-hadoop-install.log.

 3) When the script completes extra hadoop distro install and management steps
    need to be followed: 
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

