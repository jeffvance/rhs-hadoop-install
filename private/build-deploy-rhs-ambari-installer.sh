# This script will copy the current git master to jenkins, to mock
# a proper jenkins build. And afterwards, it will copy the jenkins current
# build to s3 as a release. This entire process should actually run inside of
# jenkins, rather than as a manually run shell script.
 
#### First, define the build location. ####
# NOTE: this is an intermediate target tarball directory
BUILD_LOCATION=/var/lib/jenkins/workspace/Ambari
REPO=/root/archivainstall/apache-archiva-1.3.6/data/repositories/internal
SOURCE=$(pwd) # expected to be a git directory
S3='s3://rhbd/rhs-hadoop-install'
TARBALL_PREFIX='rhs-hadoop-install-'
TARBALL_SUFFIX='.tar.gz'

# parse_cmd: use getop. Optional list of one or more directories must be
# separated only by a comma (no spaces).
#
function parse_cmd(){

  local LONG_OPTS='dirs:'

  # defaults (global variables)
  DIRS=''

  local args=$(getopt --long $LONG_OPTS -- $@)

  eval set -- "$args" # set up $1... positional args

  while true ; do
      case "$1" in
        --dirs)
            DIRS=$2; shift 2; continue
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
parse_cmd

# potentially convert .odt to .pdf, always create tarball
$SOURCE/devutils/mk_tarball.sh \
	--target-dir="$BUILD_LOCATION" \
	--pkg-version="$TAGNAME"
	--dirs=$DIRS

# git archive HEAD | gzip > $BUILD_LOCATION
cd /opt/JEFF/  ##why??

echo "Done archiving $TAGNAME to $BUILD_LOCATION..." 
ls -alth $BUILD_LOCATION 
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

# First deploy into s3: This is the preferred (but new) place where we store
# binaries:

# Now, we deploy into archiva.
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
(( $? == 0 )) && echo "Your tarball is now deployed to : $S3/$TARBALL"
exit 0
