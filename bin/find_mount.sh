#!/bin/bash
#
# find_mount.sh greps in /proc/mounts or /etc/fstab, depending on options, 
# searching for the volume or brick mount, depending on options, and returns
# the full brick or volume mount record, or the number of matching mounts, or
# shell true if the mount exists, depending on options.
# Syntax:
#   find_mount.sh [--vol|--brick] [--live|fstab] [--filter <grep-extra>] \
#                 [--rtn-mnt|--rtn-cnt|--rtn-exists] [<node>]
# Example:
#   find_mount.sh --fstab --filter $VOLNAME rhs-1.vm
# outputs the gluster voume mount on node rhs-1.vm for the supplied volume
#
# Args:
#   --vol|--brick, flag to find volume vs brick mount, default is vol.
#   --fstab|--live, flag to find mount in /etc/fstab or /proc/mounts, default
#     is live.
#   --rtn-mnt|--rtn-cnt|--rtn-exists, flag indicating what to return either via
#     output or exit status, default is rtn-mnt.
#   --filter, additional grep filter, default is "".
#   <node>, node to execute grep on, default is localhost.

# defaults
VOLMNT=1     # true
BRKMNT=0     # false
LIVE=1       # true
FSTAB=0      # false
RTN_MNT=1    # true
RTN_CNT=0    # false
RTN_EXISTS=0 # false

# parse cmd opts
opts='vol,brick,live,fstab,rtn-mnt,rtn-cnt,rtn-exists,filter:'
eval set -- "$(getopt -o '' --long $opts -- $@)"

while true; do
    case "$1" in
      --brick)
        BRKMNT=1; VOLMNT=0; shift; continue
        ;;
      --vol)
        VOLMNT=1; BRKMNT=0; shift; continue
        ;;
      --live)
        LIVE=1; FSTAB=0; shift; continue
        ;;
      --fstab)
        FSTAB=1; LIVE=0; shift; continue
        ;;
      --rtn-mnt)
        RTN_MNT=1; RTN_CNT=0; RNT_EXISTS=0; shift; continue
        ;;
      --rtn-cnt)
        RTN_CNT=1; RTN_MNT=0; RNT_EXISTS=0; shift; continue
        ;;
      --rtn-exists)
        RTN_EXISTS=1; RTN_MNT=0; RTN_CNT=0; shift; continue
        ;;
      --filter)
        FILTER="$2"; shift 2; continue
        ;;
      --)
        shift; break
        ;;
    esac
done

NODE="$1"

# handle default node
if [[ -z "$NODE" || "$NODE" == 'localhost' || "$NODE" == "$HOSTNAME" ]] ; then
  ssh=''; ssh_close=''
else
  ssh="ssh $NODE '"; ssh_close="'"
fi

# set grep file
(( LIVE )) && tgt_file='/proc/mounts' || tgt_file='/etc/fstab'

(( VOLMNT )) && type='glusterfs' || type='xfs'
(( LIVE && VOLMNT )) && type="fuse.$type"
type=" $type "

filter=''
[[ -n "$FILTER" ]] && filter="grep -E \"$FILTER\" $tgt_file |"

# handle comments if fstab
skip_comments=''
if (( FSTAB )) ; then
  skip_comments='grep -vE "^#|^ *#"'
  [[ -z "$FILTER" ]] && skip_comments+=" $tgt_file"
  skip_comments+=" |"
fi

# grep options
grep_opts=''
if (( RTN_CNT )) ; then
  grep_opts='-c'
elif (( RTN_EXISTS )) ; then
  grep_opts='-q'
fi
[[ -n "$filter" || -n "$skip_comments" ]] && tgt_file='' # already handled

out="$(eval "$ssh 
	$filter $skip_comments grep $grep_opts "$type" $tgt_file
      $ssh_close
")"
err=$?

(( RTN_EXISTS )) && exit $err

echo $out
exit 0
