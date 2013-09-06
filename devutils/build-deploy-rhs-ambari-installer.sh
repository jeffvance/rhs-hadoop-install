#This script will copy the current git master to jenkins, to mock
#a proper jenkins build. And afterwards, it will copy the jenkins current
#build to s3 as a release. This entire process should actually run inside of
#jenkins, rather than as a manually run shell script.
 
#### First, define the build location. ####
# NOTE: this is an intermediate target tarball directory
BUILD_LOCATION=/var/lib/jenkins/workspace/Ambari
REPO=/root/archivainstall/apache-archiva-1.3.6/data/repositories/internal
SOURCE=/opt/JEFF/rhs-ambari-install #expected to be a git directory
S3="s3://rhbd/rhs-ambari-install"

####### BUILD THE TAR/GZ FILE ~ THIS SHOULD RUN IN JENKINS (future) ####### 
cd $SOURCE
git pull

TAGNAME=$(git describe --abbrev=0 --tag)

#convert .odt to .pdf and create tarball
$SOURCE/devutils/mk_tarball.sh \
	--target-dir="$BUILD_LOCATION" \
	--pkg-version="$TAGNAME"

#git archive HEAD | gzip > $BUILD_LOCATION
cd /opt/JEFF/  ##why??

echo "Done archiving $TAGNAME to $BUILD_LOCATION..." 
ls -altrh $BUILD_LOCATION 
echo "proceed <ENTER>?..."
read 
#### NOW RUN SOME TESTS against the tar file (again, should run in jenkins) ##### 
/opt/JEFF/shelltest.sh ### <-- dummy script.
result=$?
echo "Test result = $result press any key to continue..."
if [[ ! $result == 0 ]]; then
      echo "Tests FAILED ! "
      exit 1
else
   echo "TEST PASSED !!!! DEPLOYING $TAGNAME !"
fi
 
### IF TESTS PASSED, we PROCEED WITH THE DEPLOYMENT !!! (yup - jenkins should run this to :) ### 

#First deploy into s3: This is the preferred (but new) place where we store binaries:

# Now, we deploy into archiva.
# target tarball versioned name
TARBALL=$(ls $BUILD_LOCATION/rhs-ambari-*.tar.gz) #expect 1 and only 1 file
TARBALL=$(basename $TARBALL)

#you can modify this however you want, this is just an example of how to push
#to s3. it works as is.
echo "Press a key to deploy to $TARBALL in $S3 - note that you need to run s3cmd --configure the first time you do this or pass the -c "
read x
s3cmd put $BUILD_LOCATION/$TARBALL $S3/$TARBALL
echo "Your tarball is now deployed to : $S3/$TARBALL"
exit 0

#Not using mvn now since using s3, but may later...
#sudo mvn deploy:deploy-file \
#-Dfile=$BUILD_LOCATION/$TARBALL \
#-Durl=file:$REPO \
#-DgroupId=rhbd \
#-DartifactId=rhs-ambari-install \
#-Dversion=$TAGNAME 

#The artifact has been created here: (after stripping tar.gz extension)
#BASEARTIFACT=$REPO/rhbd/rhs-ambari-install/$TAGNAME/${TARBALL//.tar.gz/}
#BASEARTIFACT=${BASEARTIFACT//_/.} # change version "_" back to "."

#But since maven doesnt support the tar.gz, we must move it to be a tar.gz file
#sudo mv ${BASEARTIFACT_NOTARGZ}.gz $BASEARTIFACT
#sudo chmod -R 777 $BASEARTIFACT
#sudo ls -altrh $BASEARTIFACT
########################################

#echo "Done ! The file will now be in archiva at http://23.23.239.119/archiva/repository/internal/rhbd/rhs-ambari-install/"

