#! /usr/bin/env bash
#
# This script creates the install tarball package. Currently this included the
# following files:
#
#  - install.sh: main install script, executed by the root user
#  - README.txt: readme file to be read first
#  - hosts.example: sample "hosts" config file
#  - Ambari_Configuration_Guide.pdf: config guide with Ambari Install Wizard
#      screen captures
#  - data/: directory containing:
#    - prep_node.sh: companion script, not to be executed directly
#    - gluster-hadoop-<version>.jar: Gluster-Hadoop plug-in
#    - fuse-patch.tar.gz: FUSE patch RPMs
#    - ambari.repo: repo file needed to install ambari
#    - ambari-<version>.rpms.tar.gz: Ambari server and agent RPMs
#
# The Ambari_Configuration_Guide.pdf file is exported from the git
# Ambari_Installation_Guide.odt file prior to creating the tarball.
#
# Args: $1= name of the .odt doc file to bo converted to PDF. Default is 
#       "Ambari_Configuration_Guide.odt"


DOC_FILE=${1:-Ambari_Configuration_Guide.odt}
DOC_FILE=$(basename -s .odt $DOC_FILE)
ODT_FILE="$DOC_FILE.odt"
PDF_FILE="$DOC_FILE.pdf"

# get latest package version in checked out branch
VERSION=$(git describe --abbrev=0 --tag|tr '.' '_') # x_y
TARBALL="rhs-ambari-install-$VERSION.tar.gz"

echo -e "\n\nThis tool converts the existing .odt doc file to pdf and then creates"
echo "a tarball containing the install package."
echo -e "\n  - Converting $ODT_FILE to pdf..."
f=$(ls $ODT_FILE)
if [[ -z "$f" ]] ; then
  echo "ERROR: $ODT_FILE file does not exist."
  exit 1
fi
libreoffice --headless --invisible --convert-to pdf $ODT_FILE	
if [[ $? != 0 || $(ls $PDF_FILE|wc -l) != 1 ]] ; then
  echo "ERROR: $ODT_FILE not converted to pdf."
  exit 2
fi

echo -e "\n  - Creating $TARBALL tarball..."
/bin/rm $TARBALL
/bin/tar cvzf $TARBALL  * --exclude=*.odt --exclude=hosts --exclude=devutils
if [[ $? != 0 || $(ls $TARBALL|wc -l) != 1 ]] ; then
  echo "ERROR: creation of tarball failed."
  exit 3
fi

echo
exit 0
#
# end of script
