		RHS-Hadoop Installation Development

 
  This is the readme file for rhs-hadoop-install tools developers or anyone who
  is starting with a git clone of the rhs-hadoop-install repo, rather than a pre-
  built tarball. There is a end-user's readme name README.txt which should also
  be read.

  The scripts contained in the rhs-hadoop-install repo (here) are not meant to
  be run stand-alone. They are automatically invoked by the common prep_node.sh
  script found in the glusterfs-hadoop-install repo, and sym-linked to here. The
  glusterfs-hadoop-install repo contains files and scripts common to all
  preparations of glusterfs for Hadoop workloads, including Red Hat Storage
  (RHS). The files contained in the rhs-hadoop-install repo are specific to
  preparing RHS for Hadoop workloads. rhs/ is the main directory and there are
  sub-directories under rhs/ for specific releases of RHS and/or specific Hadoop
  distros, beta releases, management tools, etc.

  The overall rhs developer's approach is to:
    - clone the rhs-hadoop-install repo,
    - run FIRST_PREP_REPO.sh to clone or refresh the glusterfs-hadoop-install
      repo and create the associated symlinks,
    - make changes,
    - execute devutils/mk_tarball with the --dirs option to create the tarball,
    - extract the tarball into an empty directory,
    - run ./install --hosts=xx --rhn-user=x --rhn-pass=y <brick-dev>.
  
  The rhs-hadoop-install repo has a dependency on the public glusterfs-hadoop-
  install community repo, and therefore this community repo must be available in
  a known location before rhs-based tarballs can be created or direct installs
  can be performed.

  After cloning the rhs-hadoop-install repo, cd to the "rhs-hadoop-install" 
  directory and execute a script named FIRST_PREP_REPO.sh. This script clones
  the common glusterfs-hadoop-install repo if not present, or refreshes it if
  present. It also creates symbolic links to every common file contained in the
  glusterfs-hadoop-install repo. DO NOT modify any of the symlinks created by 
  FIRST_PREP_REPO.sh! If changes are needed to any of these common files then
  edit the files directly from the glusterfs-hadoop-install repo.

  To test changes a tarball needs to be created first. The devutils/mk_tarball
  script will create a tarball containing some specific files and all files in
  directories listed in the --dirs option. See --help for more mk_tarball
  options. Once the tarball is created it needs to be extracted into a fresh
  empty directory. cd to the rhs-hadoop-install-<version> sub-directory and
  execute ./install.sh with the desired options (see --help) and the target
  storage brick device.

  If the tarball is targetted for a Red Hat BREW build then, in most cases, it
  should not contain any Hadoop distro-specific files.

