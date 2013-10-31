#! /bin/bash
#
# This script creates the install tarball package. Currently this includes the
# following files:
#  * rhs-hadoop-install-<verison> directory whicn contains:
#  - install.sh
#  - prep_node.sh
#  - README.txt
#  - hosts.example
#  - rhs2.0/: directory containing:
#    - Ambari_Configuration_Guide.pdf (not .odt version)
#    - ambari.repo
#    - ambari-<version>.rpms.tar.gz
#    - fuse-patch.tar.gz
#    - gluster-hadoop-<version>.jar
#    - ktune.sh: optimized RHEL 2.0.5 tuned-adm high-throughput script
#    - prep_node.sh (ambari-specific)
#
# The Ambari_Configuration_Guide.pdf file is exported from the git
# Ambari_Installation_Guide.odt file prior to creating the tarball.
#
# This script is expected to be run from a git repo so that source version
# info can be used in the tarball filename. The --source and --target-dir
# options support running the script elsewhere.
#
# There are no required command line args. All options are described in the
# usage() function.


# usage: echo the standard usage text with supported options.
#
function usage(){

  cat <<EOF

  This script converts the install guide .odt document file to pdf (if the
  doc file is present) and creates the rhs-hadoop-install tarball package.
  There are no required parameters.
  
  SYNTAX:
  
  --source     : the directory containing the source files used to create the
                 tarball (including the .odt doc file). It is expected that a
                 git clone or git pull has been done into the SOURCE directory.
                 Default is the current working directory.
  --target-dir : the produced tarball will reside in this directory. Default is
                 the SOURCE directory.
  --odt-doc    : the name of the  install guide .odt doc file. Default is"
                 "Ambari_Configuration_Guide"
  --pkg-version: the version string to be used as part of the tarball filename.
                 Default is the most recent git version in the SOURCE dir.
 
  --rhsdir     : name of the rhs sub-dir which contains extra rhs-specific
                 files, e.g. RPMs etc. 
EOF
}

# parse_cmd: getopt used to do general parsing. See usage function for syntax.
#
function parse_cmd(){

  local OPTIONS='h'
  local LONG_OPTS='source:,target-dir:,pkg-version:,odt-doc:,rhsdir:,help'

  # defaults (global variables)
  SOURCE=$PWD
  TARGET=$SOURCE
  PKG_VERSION=''
  ODT_DOC='Ambari_Configuration_Guide'
  RHS_DIR=''

  local args=$(getopt -n "$(basename $0)" -o $OPTIONS --long $LONG_OPTS -- $@)
  (( $? == 0 )) || { echo "$SCRIPT syntax error"; exit -1; }

  eval set -- "$args" # set up $1... positional args
  while true ; do
      case "$1" in
        -h|--help)
	   usage; exit 0
	;;
	--source)
	   SOURCE=$2; shift 2; continue
	;;
	--target-dir)
	   TARGET=$2; shift 2; continue
	;;
	--pkg-version)
	   PKG_VERSION=$2; shift 2; continue
	;;
	--odt-doc)
	   ODT_DOC=$2; shift 2; continue
	;;
	--rhsdir)
	   RHS_DIR=$2; shift 2; continue
	;;
        --)  # no more args to parse
	   shift; break
        ;;
        *) echo "Error: Unknown option: \"$1\""; exit -1
        ;;
      esac
  done

  # note: supplied version arg trumps git tag/versison
  [[ -z "$PKG_VERSION" && -d ".git" ]] && \
	PKG_VERSION=$(git describe --abbrev=0 --tag)
  [[ -n "$PKG_VERSION" ]] && PKG_VERSION=${PKG_VERSION//./_} # x.y -> x_y
  [[ -z "$PKG_VERSION" ]] && { \
	echo "ERROR: package version not supplied and no git environment present.";
	exit -1; }

  # verify source, target and rhsdir dirs
  [[ -d "$SOURCE" ]] || {
	echo "ERROR: \"$SOURCE\" source directory missing."; exit -1; }
  [[ -d "$TARGET" ]] || {
	echo "ERROR: \"$TARGET\" target directory missing."; exit -1; }
  [[ -n "$RHS_DIR" && ! -d $RHS_DIR ]] && {
	echo "ERROR: rhsdir does not exist or is not a directory"; exit -1; }
}

# convert_odt_2_pdf: if possible convert the .odt doc file under the user's
# cwd to a pdf file using libreoffice. Report warning if this can't be done.
#
function convert_odt_2_pdf(){

  # user can provide docfile.odt or just docfile w/o .odt
  ODT_DOC=${ODT_DOC%.odt} # remove .odt extension if present

  local ODT_FILE="$ODT_DOC.odt"
  local PDF_FILE="$ODT_DOC.pdf"

  echo -e "\n  - Converting \"$ODT_FILE\" to pdf..."

  [[ -n "$RHS_DIR" ]] && cd $RHS_DIR

  if ls $ODT_FILE ; then
    libreoffice --headless --invisible --convert-to pdf $ODT_FILE	
    if [[ $? != 0 || $(ls $PDF_FILE|wc -l) != 1 ]] ; then
      echo "WARN: $ODT_FILE not converted to pdf"
    fi
  else
    echo "WARN: $ODT_FILE file does not exist, skipping this step."
  fi

  [[ -n "$RHS_DIR" ]] && cd -
}

# create_tarball: create a versioned directory in the user's cwd, copy the
# target contents to that dir, create the tarball, and finally rm the
# versioned dir.
#
function create_tarball(){

  # tarball contains the rhs-hadoop-install-<version> dir, thus we have to copy
  # target files under this dir, create the tarball and then rm the dir
  local TARBALL_PREFIX="rhs-hadoop-install-$PKG_VERSION"
  local TARBALL="$TARBALL_PREFIX.tar.gz"
  local TARBALL_DIR="$TARBALL_PREFIX" # scratch dir not TARGET dir
  local TARBALL_PATH="$TARBALL_DIR/$TARBALL"
#local FILES_TO_TAR=(*.sh README.* hosts.example $(ls -d */|grep -v devutils/))
  local FILES_TO_TAR='*.sh README.* hosts.example'

  echo -e "\n  - Creating $TARBALL tarball in $TARGET"
  rm $TARBALL

  # create temp tarball dir and copy subset of content there
  rm -rf $TARBALL_DIR
  mkdir $TARBALL_DIR
  [[ -n "$RHS_DIR" ]] && FILES_TO_TAR+=" $RHS_DIR"
  cp -R $FILES_TO_TAR $TARBALL_DIR

  tar cvzf $TARBALL $TARBALL_DIR
  if [[ $? != 0 || $(ls $TARBALL|wc -l) != 1 ]] ; then
    echo "ERROR: creation of tarball failed."
    exit 1
  fi
  rm -rf $TARBALL_DIR

  # move tarball file to TARGET dir
  [[ "$TARGET" == "$PWD" ]] || mv $TARBALL $TARGET
}


## main ##
##
parse_cmd $@

echo -e "This script converts the existing .odt doc file to pdf and then creates"
echo "a tarball containing the install package."
echo
echo "  Source dir:  $SOURCE"
echo "  Target dir:  $TARGET"

convert_odt_2_pdf
create_tarball

echo
#
# end of script
