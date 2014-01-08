                           devutils tools


passwordless-ssh.sh:
-------------------
  This script sets up password-less SSH as required for the RHS cluster. A local
  "hosts" file of "ip-address hostname" pairs contains the list of hosts for
  which password-less SSH is configured. Additionally, the first host in this
  file will be able to password-less SSH to all other hosts in the file. Thus,
  after running this script the user will be able to password-less SSH from
  localhost to all hosts in the hosts file, and from the first host to all
  other hosts defined in the file.

  "host" file format:
     IP-address   simple-hostname
     IP-address   simple-hostname ...

  Options:

   --hosts     <path> : path to "hosts" file. This file contains a list of
                        "IP-addr hostname" pairs for each node in the cluster.
                        Default: "./hosts".
   -v|--version       : Version of the script.
   -h|--help          : help text (this).
   --sethostname      : sethostname=hostname on each node (default).
   --noset|nosethostname : do not set the hostname on each node (override
                        default).
   --verbose          : causes more output. Default is semi-quiet.

