#!/bin/bash
#
# This script creates the RHS install tarball package. Currently this includes 
# the following files:
#  * rhs-hadoop-install-<verison> directory which contains:
#   - hosts.example: sample "hosts" config file.
#   - install.sh: the main install script, executed by the root user.
#   - prep_node.sh: companion script, not to be executed directly.
#   - README.txt: this file.
#   - devutils/: utility directory.
#   - plus optional directories via the --dirs option.
#
# This script is expected to be run from a git repo so that source version
# info can be used in the tarball filename. The --source and --target-dir
# options support running the script elsewhere.
#
# There are no required command line args. All options are described in the
# usage() function.

# source common constants and functions
if [[ -f functions ]] ; then source functions
elif [[ -f ../functions ]] ; then source ../functions
else echo "Missing \"functions \" library"; exit -1
fi

# usage: echo the standard usage text with supported options.
#
function usage(){

  cat <<EOF

  This script may convert the install guide .odt document file to pdf (if the
  doc file is present in one of the supplied --dirs=) and creates the rhs-
  hadoop-install tarball package.

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
  --dirs       : list of directory names, separated by only a comma. The
                 contents of these directories will be included in the tarball
                 and ultimately installed by the installation scripts. NOTE: 
                 collecting files within each dir is *not* recursive, meaning
                 sub-dirs within the supplied dir names are ignored.
EOF
}

# parse_cmd: getopt used to do general parsing. See usage function for syntax.
#
function parse_cmd(){

  local OPTIONS='h'
  local LONG_OPTS='source:,target-dir:,pkg-version:,odt-doc:,dirs:,help'
  local dir; local i

  # defaults (global variables)
  SOURCE=$PWD
  TARGET=$SOURCE
  PKG_VERSION=''
  ODT_DOC='Ambari_Configuration_Guide'
  DIRS=(devutils/) # array, always include contents of devutils/

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
	--dirs)
	   DIRS+=(${2//,/ }) # replace comma with space and append to array
	   shift 2; continue
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

  # verify source and target
  [[ -d "$SOURCE" ]] || {
	echo "ERROR: \"$SOURCE\" source directory missing."; exit -1; }
  [[ -d "$TARGET" ]] || {
	echo "ERROR: \"$TARGET\" target directory missing."; exit -1; }

  # verify any extra directories
  for (( i=1; i<${#DIRS[@]}; i++ )) ; do # skip devutils/ entry
      dir="${DIRS[$i]}"
      if [[ ! -d "$dir" ]] ; then
	echo "ERROR: extra directory \"$dir\" does not exist in $PWD"
	exit -1
      fi
  done
}

# convert_odt_2_pdf: if possible convert the .odt doc file under the user's
# cwd to a pdf file using libreoffice. Report warning if this can't be done.
#
function convert_odt_2_pdf(){

  # user can provide docfile.odt or just docfile w/o .odt
  ODT_DOC=${ODT_DOC%.odt} # remove .odt extension if present

  local ODT_FILE="$ODT_DOC.odt"
  local PDF_FILE="$ODT_DOC.pdf"

  # get dirname of odt file and cd to it if match
  match_dir "$ODT_FILE" "$INCLUDED_FILES" # sets MATCH_DIR var if match
  [[ -z "$MATCH_DIR" ]] && {
    echo "INFO: $ODT_FILE file does not exist, no PDF conversion needed.";
    return; }

  cd $MATCH_DIR
  echo -e "\n  - Converting \"$ODT_FILE\" to pdf..."

  libreoffice --headless --invisible --convert-to pdf $ODT_FILE	
  [[ $? != 0 || $(ls $PDF_FILE|wc -l) != 1 ]] && {
    echo "WARN: $ODT_FILE not converted to pdf"; }

  cd -
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
  local FILES_TO_TAR="*.sh \
	functions \
	*sudoers* \
	hosts.example \
	README.* \
	$INCLUDED_FILES" 

  echo -e "\n  - Creating $TARBALL tarball in $TARGET"
  rm -f $TARBALL

  # create temp tarball dir and copy all files to be tar'd to tar dir
  rm -rf $TARBALL_DIR
  mkdir $TARBALL_DIR
  cp --parent $FILES_TO_TAR $TARBALL_DIR

  # exclude the script used to prepare the rhs repo with the common files
  tar cvzf $TARBALL $TARBALL_DIR --exclude FIRST_PREP_REPO.sh
  if [[ $? != 0 || $(ls $TARBALL|wc -l) != 1 ]] ; then
    echo "ERROR: creation of tarball failed."
    exit 1
  fi
  rm -rf $TARBALL_DIR

  # move tarball file to TARGET dir
  [[ "$TARGET" == "$PWD" ]] || mv $TARBALL $TARGET
}


## main ##
##      ##
parse_cmd $@

echo -e "This script converts the existing .odt doc file to pdf and then creates"
echo "a tarball containing the install package."
echo
echo "  Source dir:  $SOURCE"
echo "  Target dir:  $TARGET"
echo "  Extra dirs:  ${DIRS[@]}"

# format for INCLUDED_FILES: "dir1/file1 dir1/f2 dir1/dir2/f ..."
# note: DIRS always contains at least the devutils dir
INCLUDED_FILES=''
for dir in ${DIRS[@]} ; do
    INCLUDED_FILES+="$(find $dir -maxdepth 1 -type f) "
done

convert_odt_2_pdf
create_tarball

echo
#
# end of script
