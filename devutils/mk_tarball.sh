#! /bin/bash
#
# This script creates the install tarball package. Currently this includes the
# following files:
#  * rhs-ambari-install-<verison> directory whicn contains:
#  - install.sh: main install script, executed by the root user
#  - README.txt: set up and run instructions
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
# Args: $1= package version number which usually corresponds to the install.sh
#       version. Default is the most recent git version on the current branch.
#       Version is blank if not supplied this scipt is not run in a git env.
# Args: $2= name of the .odt doc file to bo converted to PDF. Default is
#       "Ambari_Configuration_Guide.odt"

VERSION=${1:-}
DOC_FILE=${2:-Ambari_Configuration_Guide.odt}

# get latest package version in checked out branch
[[ -z "$VERSION" && -e .git ]] && VERSION=$(git describe --abbrev=0 --tag)
[[ -n "$VERSION" ]] && VERSION=${VERSION//./_} # x_y

DOC_FILE=$(basename -s .odt $DOC_FILE)
ODT_FILE="$DOC_FILE.odt"
PDF_FILE="$DOC_FILE.pdf"

TARBALL_PREFIX="rhs-ambari-install-$VERSION"
TARBALL="$TARBALL_PREFIX.tar.gz"
TARBALL_DIR="$TARBALL_PREFIX"
TARBALL_PATH="$TARBALL_DIR/$TARBALL"
FILES_TO_TAR=(install.sh README.txt Ambari_Configuration_Guide.pdf data/)

# get latest package version in checked out branch


echo -e "\n\nThis tool converts the existing .odt doc file to pdf and then creates"
echo "a tarball containing the install package."
echo -e "\n  - Converting $ODT_FILE to pdf..."
f=$(ls $ODT_FILE)
if [[ -z "$f" ]] ; then
  echo "WARN: $ODT_FILE file does not exist, skipping this step."
else
  libreoffice --headless --invisible --convert-to pdf $ODT_FILE	
  if [[ $? != 0 || $(ls $PDF_FILE|wc -l) != 1 ]] ; then
    echo "WARN: $ODT_FILE not converted to pdf."
  fi
fi

echo -e "\n  - Creating $TARBALL tarball..."
[[ -e $TARBALL ]] && /bin/rm $TARBALL
# create temp tarball dir and copy subset of content there
[[ -d $TARBALL_DIR ]] && /bin/rm -rf $TARBALL_DIR
/bin/mkdir $TARBALL_DIR
###/bin/cp -R !($TARBALL_DIR|.git|*.odt|devutils|hosts) $TARBALL_DIR
for f in "${FILES_TO_TAR[@]}" ; do
  /bin/cp -R $f $TARBALL_DIR
done
/bin/tar cvzf $TARBALL  $TARBALL_DIR
if [[ $? != 0 || $(ls $TARBALL|wc -l) != 1 ]] ; then
  echo "ERROR: creation of tarball failed."
  exit 1
fi
/bin/rm -rf $TARBALL_DIR

echo
exit 0
#
# end of script
