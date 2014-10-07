#!/bin/bash
#
# find_default_vol.sh outputs the name of the default volume. This is the first
# volume appearing in the core-site's "fs.glusterfs.volumes" property. Exits
# with 1 on errors.
# Args:
#   -n=(optional) any storage node, if not supplied then localhost must be a
#      storage node.

core_site='/etc/hadoop/conf/core-site.xml'
prop='fs.glusterfs.volumes' # list of 1 or more vols, 1st is default

# parse cmd opts
while getopts ':n:' opt; do
    case "$opt" in
      n)
        rhs_node="$OPTARG"
        ;;
      \?) # invalid option
        ;;
    esac
done

[[ -z "$rhs_node" ]] && rhs_node="$HOSTNAME"

[[ "$rhs_node" == "$HOSTNAME" ]] && ssh='' || ssh="ssh $rhs_node"

vol="$(eval "$ssh [[ -f $core_site ]] &&
	sed -n '/$prop/,/<\/property>/{/<value>/p}' $core_site 2>&1")" 
(( $? != 0 )) || [[ -z "$vol" ]] && {
  echo "$rhs_node: \"$prop\" property value is missing from $core_site"; 
  exit 1; }

vol=${vol#*>} # delete leading <value>
vol=${vol%<*} # delete trailing </value>, could be empty
vol=${vol%,*} # extract 1st or only volname, can be ""

echo "$vol"
exit 0
