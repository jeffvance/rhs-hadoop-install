#!/bin/bash
#
# Copyright (c) 2013 Red Hat, Inc.
# License: Apache License v2.0
# Author: Jeff Vance <jvance@redhat.com>
#
# This script *must* be run *before* executing anything in the
# rhs-hadoop-install repo!!
#
# This script verifies that the *required* glusterfs-hadoop-install repo has
# been cloned in the expected location (../glusterfs-hadoop-install), clones 
# this repo if not found, and then creates symlinks to the common files
# contained in this repo. The common files in the glusterfs-hadoop-install repo
# are necessary in order to create an rhs-hadoop tarball.
# 

GLUSTERFS_HADOOP_INSTALL_DIR="../glusterfs-hadoop-install"
GLUSTERFS_HADOOP_INSTALL_GIT="https://github.com/jeffvance/glusterfs-hadoop-install"


cat <<EOF

$(basename $0) ensures that the rhs-hadoop-install repo you're in has the
required common files residing in your glusterfs-hadoop-install repo. This repo
will be cloned if not already present in the $GLUSTERFS_HADOOP_INSTALL_DIR
directory, or will be refreshed if it already exists.

If needed, symlinks are created to point to all of the common files in the
glusterfs-hadoop-install repo.

EOF


if [[ ! -d "$GLUSTERFS_HADOOP_INSTALL_DIR" ]] ; then
  echo "Missing required glusterfs-hadoop-install repo... cloning now..."
  cd ..
  git clone $GLUSTERFS_HADOOP_INSTALL_GIT
  cd -
else
  echo "Refreshing potentially stale glusterfs-hadoop-install repo"
  cd $GLUSTERFS_HADOOP_INSTALL_DIR
  git pull
  cd -
fi

# rm existing symlinks, if any, to start fresh
find -type l -exec rm {} \;

# create symlinks to the common files in glusterfs-hadoop-install which are
# needed for all rhs-hadoop-install related builds/installs
# note: we excluded the glusterfs/ dir since its content is strictly needed for
#  fedora (non-rhs) installs
cnt=0
COMMON_FILES="$(find $GLUSTERFS_HADOOP_INSTALL_DIR -type f -not -path "*/glusterfs/*" -not -path "*/.*" -not -name README.txt -not -name hosts)"

for common in $COMMON_FILES ; do
    f="$(basename $common)"
    [[ -L "$f" ]] && continue # symlink is already there
    [[ -f "$f" ]] && rm -f $f # rm non-symlink common file
    echo "  Creating symlink to common file: $common"
    ln -s $common $f
    (( $? == 0 )) && ((cnt+=1)) || echo "ERROR: failed to create symlink $f"
done

echo "Done. $cnt symlinks created"

cat <<EOF

Now that the common files and scripts are available in your rhs-hadoop-install
directory, the next step is to examine rhs/ and its sub-directories content, and
create a tarball via the rhs-install-deploy repo's mk_tarball.sh script with the
appropriate --dirs directory names. Eg:
  mk_tarball.sh --dirs rhs,rhs2.1,hdp2.x-beta

Note: each dir specified in --dirs is stand-alone meaning NON-recursive.

The created tarball will contain all of the common files and the files within
each of the dirs specified in the --dirs option above. The tarball can then be
used as the source for a BREW build, deployed to s3 or OpenStack, or simply
extracted in place. cd to the rhs-hadoop-install-<version> directory contained
in the tarball, read the README files, create a local "hosts" file, and run 
./install.sh <brick-dev>

EOF
