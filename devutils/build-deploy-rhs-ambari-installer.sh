#This script will copy the current git master to jenkins, to mock
#a proper jenkins build. And afterwards, it will copy the jenkins current build to archiva as a release. This entire process should actually run inside of jenkins, rather than as a manually run shell script.
 
#### First, define the build location. ####
BUILD_LOCATION=/var/lib/jenkins/workspace/Ambari/rhs-ambari-install-current.tar.gz

SOURCE=/opt/JEFF/rhs-ambari-install

####### BUILD THE TAR/GZ FILE ~ THIS SHOULD RUN IN JENKINS (future) ####### 
cd $SOURCE
git pull

### Generally the cut SHOULD NOT be required ## 
TAGNAME=`git describe --tags | sed s/v//g | cut -d'-' -f 1`

$SOURCE/devutils/mk_tarball.sh #converts .odt to .pdf and creates tarball
cp $SOURCE/rhs-ambari-install*gz $BUILD_LOCATION

#git archive HEAD | gzip > $BUILD_LOCATION
cd /opt/JEFF/

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
      return 1
else
   echo "TEST PASSED !!!! DEPLOYING $TAGNAME !"
fi
 
### IF TESTS PASSED, we PROCEED WITH THE DEPLOYMENT !!! (yup - jenkins should run this to :) ### 

sudo mvn deploy:deploy-file \
-Dfile=$BUILD_LOCATION \
-Durl=file:/root/archivainstall/apache-archiva-1.3.6/data/repositories/internal \
-DgroupId=rhbd \
-DartifactId=rhs-ambari-install \
-Dversion=$TAGNAME 

########################################

echo "Done ! The file will now be in archiva at http://23.23.239.119/archiva/repository/internal/rhbd/rhs-ambari-install/"

