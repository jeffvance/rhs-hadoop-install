		   RHS-Hadoop Installation -- rhs/ directory


The rhs/ directory contains files and scripts common to all versions of Red Hat
Storage (RHS). pre_install.sh scripts are executed before prep_node.sh performs
most of its tasks; whereas, post_install.sh scripts (if any) are executed when
prep_node.sh is finished with its tasks.

There may be sub-directories under rhs/ to perform setup for specific versions
of RHS, and/or to make pre-release versions available. Each of these sub-
directories will contain its own README file explaining the contents of the
directory.

