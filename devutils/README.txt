mk_tarball:

$1 optional, git version string/tag. Default is to use git to get the version
  (= most recent tag) for the current branch (typically master).
$2 optional, .odt doc name. Default is "Ambari_Configuration_Guide.odt"

This script converts the .odt file (if present) to a PDF and then creates a
tarball containing the minimal set of files necessary for RHS-Ambari installs.

The script is expected to be run in the same dir where a git pull or git clone
is done.
-
