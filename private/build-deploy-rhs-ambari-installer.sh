#!/bin/bash
#
# This script will copy the current git master to jenkins, to mock
# a proper jenkins build. And afterwards, it will copy the jenkins current
# build to s3 as a release. This entire process should actually run inside of
# jenkins, rather than as a manually run shell script.
 
#### First, define the build location. ####
# NOTE: this is an intermediate target tarball directory
BUILD_LOCATION=/var/lib/jenkins/workspace/Ambari
REPO=/root/archivainstall/apache-archiva-1.3.6/data/repositories/internal
SOURCE=$(pwd) # expected to be a git directory
S3_BKT='s3://rhbd'
S3_1_X_OBJ="$S3_BKT/rhs-hadoop-install/1.x" # location for hadoop 1.x files
S3_2_X_OBJ="$S3_BKT/rhs-hadoop-install/2.x" # location for hadoop 2.x files
TARBALL_PREFIX='rhs-hadoop-install-'
TARBALL_SUFFIX='.tar.gz'

# parse_cmd: use getop. Optional list of one or more directories must be
# separated only by a comma (no spaces).
#
function parse_cmd(){

  local OPTIONS='D:12'
  local LONG_OPTS='dirs:,1x,2x'

  # defaults (global variables)
  DIRS='' # default is no extra dirs
  One_X=false
  Two_X=true # default is 2.xx

  # note: there seems to be a bug in getopt whereby it won't parse correctly
  #   unless short options are also provided. Using --long only causes --dirs
  #   to be skipped.
  local args=$(getopt -n "$(basename $0)" -o $OPTIONS --long $LONG_OPTS -- $@)

  eval set -- "$args" # set up $1... positional args

  while true ; do
      case "$1" in
        -D|--dirs)
            DIRS=$2; shift 2; continue
        ;;
        -1|--1x)
            One_X=true; Two_X=false; shift 1; continue
        ;;
        -2|--2x)
            One_X=false; Two_X=true; shift 1; continue
        ;;
        --)  # no more args to parse
            shift; break
        ;;
      esac
  done
}

# main #
#      #

####### BUILD THE TAR/GZ FILE ~ THIS SHOULD RUN IN JENKINS (future) ####### 
cd $SOURCE
git pull # this loads *all* directories in the repo. However, the resulting 
	 # deployment may include a only the devutils/ dir, meaning the other
	 # dirs are ignored, or may include a subset of the dirs. Most likely
	 # all dirs will not be part of the deployment.

TAGNAME="$(git describe --abbrev=0 --tag)"
TARBALL="$TARBALL_PREFIX${TAGNAME//./_}$TARBALL_SUFFIX" # s/./_/ in tag

# parse cmdline options
parse_cmd $@

# potentially convert .odt to .pdf, always create tarball
$SOURCE/devutils/mk_tarball.sh \
	--target-dir="$BUILD_LOCATION" \
	--pkg-version="$TAGNAME" \
	--dirs=$DIRS

echo
echo "Proceed? <ENTER>"
read 

if [[ -f "$BUILD_LOCATION/$TARBALL" ]] ; then
  git archive HEAD | gzip >$BUILD_LOCATION
else
  echo "$BUILD_LOCATION/$TARBALL was not built"
  exit 1
fi
	
echo "Done archiving $TAGNAME to $BUILD_LOCATION..." 
ls -rlth $BUILD_LOCATION 

echo
echo "Proceed? <ENTER>"
read 

#### NOW RUN SOME TESTS against the tar file (again, should run in jenkins)
/opt/JEFF/shelltest.sh ### <-- dummy script.
result=$?
echo "Test result = $result press any key to continue..."
if [[ ! $result == 0 ]]; then
      echo "Tests FAILED !"
      exit 1
else
   echo "TEST PASSED !!!! DEPLOYING $TAGNAME !"
fi
### IF TESTS PASSED, we PROCEED WITH THE DEPLOYMENT !!!

# Deploy into s3: This is the preferred (but new) place where we store
# binaries:
[[ "$One_X" == true ]] && S3="$S3_1_X_OBJ" || S3="$S3_2_X_OBJ"
echo
echo "Press a key to deploy to $TARBALL in $S3."
echo "Note that you need to run: \"s3cmd --configure\" the first time you do"
echo "this or pass the -c option."
echo "    build   -> $BUILD_LOCATION"
echo "    tarball -> $TARBALL"
echo "    s3      -> $S3"
echo "Proceed? <ENTER>"
read
s3cmd put $BUILD_LOCATION/$TARBALL $S3/$TARBALL
err=$?
(( err == 0 )) && echo "Your tarball is now deployed to $S3/$TARBALL" || \
	echo "s3cmd put error $err"
echo
exit 0
