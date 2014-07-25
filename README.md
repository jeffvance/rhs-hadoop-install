		        RHS-Hadoop Installation

== Overview ==

  rhs-hadoop-install is a package that prepares Red Hat Storage (RHS, built on
  glusterfs) for Hadoop workloads. It is easy to install via yum and simple to
  execute via the main scripts found in /usr/share/rhs-hadoop-install.

  RHS sits on top of XFS, which is on top of LVM, which runs on RAID-6 disks.
  This environment is required of every data storage node in the cluster. It is
  expected that all nodes in the storage cluster have RHS 3.0+ installed, and
  password-less SSH is necessary between the "deploy-from" node (from which the
  main scripts are run, and which is typically is the Ambari management server)
  to all nodes in the cluster.

  The recommended topology for a big data RHS cluster is one RHEL 6.5 Ambari
  management server, 1 (different) RHEL 6.5 Yarn-master server, and N (as a
  multiple of 2) RHS 3.0 storage nodes. It is possible to combine the Yarn node
  and the Ambari node, or even for these servers to be storage nodes, and while
  this topology is supported, it is not recommended.

  To install this package:
   - cd /usr/share,
   - yum install rhs-hadoop-install,

  To prepare RHS for Hadoop:
   - cd /usr/share/rhs-hadoop-install,
   - execute ./setup_cluster.sh --yarn-master <node> --hadoop-mgmt-node <node> \
               <node1>:<brick-mnt>:<brick-dev> \
               <node2>[:<brick-mnt>][:<brick-dev>] ...
   - execute ./create_vol.sh <newVolName> <vol-mount-prefix> \
               <node1>:<brick-mnt> <node2>[:<brick-mnt>] ...
   - follow the steps for using the Ambari install wizard
   - execute ./enable_vol.sh --yarn-master <node> --rhs-node <node> <volName>
   - execute ./setup_container_executor.sh on each node
   - see /var/log/rhs-hadoop-install.log for install details.

  To add nodes to an existing cluster:
   - execute ./setup_cluster.sh --yarn-master <node> --hadoop-mgmt-node <node> \
               <new-node1>:<brick-mnt>:<brick-dev> \
               <new-node2>[:<brick-mnt>][:<brick-dev>] ...
     (nodes must be added in pairs)
   - ssh to any storage node and execute:
       gluster volume add-brick <oldVolName> <new-node1>:<brick-mnt> \
               <new-node2>:<brick-mnt>
   - access the Ambari mgmt web UI and do the following:
     . stop all services
     . navigate to "add new nodes" and select manual registration,
     . select "all" for Slaves and Clients
     . use defaults in the Configuration screen
     . click Deploy,
   - ssh to the new storage node and execute:
       ./setup_container_executor.sh # on each new node

