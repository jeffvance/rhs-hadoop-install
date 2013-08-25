#! /bin/bash
#
# This script creates the install tarball package. Currently this includes the
# following files:
#  * rhs-ambari-install-<verison> directory whicn contains:
#  - install.sh
#  - README.txt
#  - hosts.example
#  - Ambari_Configuration_Guide.pdf (not .odt version)
#  - data/: directory containing:
#    - prep_node.sh
#    - gluster-hadoop-<version>.jar
#    - fuse-patch.tar.gz
#    - ambari.repo
#    - ambari-<version>.rpms.tar.gz
#
# The Ambari_Configuration_Guide.pdf file is exported from the git
# Ambari_Installation_Guide.odt file prior to creating the tarball.
#
# Args: $1= package version number which usually corresponds to the install.sh
#       version. Default is the most recent git version on the current branch.
#       Version is blank if not supplied, or if this scipt is not run in a git
#       environment.
# Args: $2= name of the .odt doc file to bo converted to PDF. Default is
#       "Ambari_Configuration_Guide.odt"

### OPTIONAL PARAMETERS, NOT REQUIRED IF libreoffice path and source is local

#The normal defaults..
LIBREOFFICE=libreoffice
SOURCE=.

#To work on jenkins: 
#LIBREOFFICE=/usr/bin/libreoffice4.1
#SOURCE=/opt/JEFF/rhs-ambari-install

VERSION=${1:-}

DOC_FILE=${2:-$SOURCE/Ambari_Configuration_Guide.odt}
DOC_FILE=$SOURCE/Ambari_Configuration_Guide.odt

# get latest package version in checked out branch
# note: supplied version arg trumps git tag/versison


#Create version from GIT metadata.  This is the "right" way to do it for CI.
[[ -z "$VERSION" && -e .git ]] && VERSION=$(git describe --abbrev=0 --tag)

# TODO: Remove the VERSION//./_ replacement.  This seems dangerous to scripts
# Expecting version input to be faithfully observerd.
[[ -n "$VERSION" ]] && VERSION=${VERSION//./_} # x.y -> x_y


# convert_odt_2_pdf: if possible convert the .odt doc file in the user's cwd
# to a pdf file using libreoffice. Report warning if this can't be done.
#
function convert_odt_2_pdf(){

  # user can provide docfile.odt or just docfile w/o .odt
  echo $DOC_FILE
  
  #Declarative hipster stuff that works on Jeff's fedora to extract basename .
  #DOC_FILE=$(basename -s .odt $DOC_FILE)
  
  #Simpler version of basename command: works on any linux. 
  DOC_FILE=`echo $DOC_FILE | cut -f 1 -d'.'`

  local ODT_FILE="$DOC_FILE.odt"
  local PDF_FILE="$DOC_FILE.pdf"
  local f

  echo -e "\n  - Converting file='$ODT_FILE' to pdf..."

  f=$(ls $ODT_FILE)
  if [[ -z "$f" ]] ; then
    echo "WARN: $ODT_FILE file does not exist, skipping this step."
  else
    $LIBREOFFICE --headless --invisible --convert-to pdf $ODT_FILE	
    if [[ $? != 0 || $(ls $PDF_FILE|wc -l) != 1 ]] ; then
      echo "WARN: $ODT_FILE not converted to pdf."
    fi
  fi
}

# create_tarball: create a versioned directory in the user's cwd, copy the
# target contents to that dir, create the tarball, and finally rm the
# versioned dir.
#
function create_tarball(){

  # tarball contains the rhs-ambari-install-<version> dir, thus we have to copy
  # target files under this dir, create the tarball and then rm the dir
  local TARBALL_PREFIX="rhs-ambari-install-$VERSION"
  local TARBALL="$TARBALL_PREFIX.tar.gz"
  local TARBALL_DIR="$TARBALL_PREFIX"
  local TARBALL_PATH="$TARBALL_DIR/$TARBALL"
  local FILES_TO_TAR=(install.sh README.txt Ambari_Configuration_Guide.pdf data/)
  local f

  echo -e "\n  - Creating $TARBALL tarball... for version : $VERSION"
  [[ -e $TARBALL ]] && /bin/rm $TARBALL

  # create temp tarball dir and copy subset of content there
  [[ -d $TARBALL_DIR ]] && /bin/rm -rf $TARBALL_DIR
  /bin/mkdir $TARBALL_DIR
  for f in "${FILES_TO_TAR[@]}" ; do
    /bin/cp -R $f $TARBALL_DIR
  done

  /bin/tar cvzf $TARBALL $TARBALL_DIR
  if [[ $? != 0 || $(ls $TARBALL|wc -l) != 1 ]] ; then
    echo "ERROR: creation of tarball failed."
    exit 1
  fi
  /bin/rm -rf $TARBALL_DIR
}


## main ##
##
echo -e "\n\nThis script converts the existing .odt doc file to pdf and then creates"
echo "a tarball containing the install package."

convert_odt_2_pdf
create_tarball

echo
#
# end of script
