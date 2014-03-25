		RHS-Hadoop Installation Development

 
  This is the readme file for rhs-hadoop-install tools developers or anyone who
  is starting with a git clone of the rhs-hadoop-install repo, rather than a 
  package.  There is a end-user's readme named README.txt which should also be
  read.

  The scripts contained in the rhs-hadoop-install repo (here) are not meant to
  be run stand-alone. They are automatically invoked by the common prep_node.sh
  script found in the glusterfs-hadoop-install repo, and sym-linked to here. The
  glusterfs-hadoop-install repo contains files and scripts common to all
  preparations of glusterfs for Hadoop workloads, including Red Hat Storage
  (RHS). The files contained in the rhs-hadoop-install package are specific to
  preparing RHS for Hadoop workloads. rhs/ is the main directory and there may
  be sub-directories under rhs/ for specific releases of RHS and/or specific
  Hadoop distros, beta releases, management tools, etc.

  The overall rhs developer's approach is to:
    - clone the rhs-hadoop-deploy repo,
    - clone the rhs-hadoop-install repo,
    - cd to rhs-hadoop-install
    - run ./FIRST_PREP_REPO.sh to clone or refresh the glusterfs-hadoop-install
      repo and create the associated symlinks,
    - make changes,
    - execute rhs-install-deploy/mk_tarball with the --dirs option to create a 
      tarball,
    - extract the rhs-hadoop-install-<version>.tar.gz tarball into a fresh,
      empty directory,
    - cd to rhs-hadoop-install-<version>
    - run ./install [--verbose=n] [--hosts=xx] <block-dev>.
  
Details:

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
  edit the files directly from the glusterfs-hadoop-install repo, and push up
  your changes.

  To test a tarball needs to be created first. The rhs-hadoop-deploy/mk_tarball
  script creates a tarball containing some specific files and all files in
  directories listed in the --dirs option. See --help for more mk_tarball
  options. Once the tarball is created it needs to be extracted into a fresh
  empty directory. cd to the rhs-hadoop-install-<version> sub-directory and
  execute ./install.sh with the desired options (see --help) and the target
  storage block device.

  If the tarball is targetted for a Red Hat BREW build then, in most cases, it
  should not contain any Hadoop distro-specific files.

Sub-directories:
 
  There is at least one sub-directory under rhs-hadoop-install, namely rhs/,
  which has its own README file. There may be sub-directories under rhs/
  depending on how install needs evolve.

  Each sub-directory may contain a script named "pre_install.sh" and/or a script
  named "post_install.sh". These are the only scripts within a sub-directory
  that are automatically executed by install.sh. As expected, "pre_install.sh"
  is invoked as the first step of the prep_node.sh script, and "post_install.sh"
  is invoked as the last step of prep_node.sh. Note: the prep_node.sh script is
  automatically invoked by install.sh script, once per node.

  Sub-directory *_install.sh scripts may execute additional programs and/or
  scripts, but install.sh script only executes one "pre_install" and one 
  "post_install" script per sub-directory. Note: sub-directory *_install.sh
  scripts are optional and if not present no sub-directory scripts are executed,
  even if other executable scripts are present in the sub-directory. If there
  are multiple sub-directories in the package, each with pre_|post_ install.sh
  scripts, the execution order is determined by the alphabetic order of the sub-
  directory names.

