#!/bin/bash
#
# parse_config_file.sh outputs the selected option(s) from the supplied config
# file. If more than one options is specified (not really recommended) the 
# output order is hard-coded in the script, not necessarily the option order.
# Syntax:
#  --nodes: nodes= value
#  --blk-devs: blk-devs= value
#  --brick-mnt: brick-mnt= value
#  --vol-mnt-prefix: vol-mnt-prefix value
#  --yarn-server: yarn-server= value
#  --hadoop-mgmt-server: hadoop-mgmt-server value
#  --volume <volName>: output the section for this volume
#  $1=config file

opts='nodes,blk-devs,brick-mnt,vol-mnt-prefix,yarn-server,hadoop-mgmt-server,volume:'
tmpconf="$(mktemp --suffix _rhs_hadoop_install.conf)"
# assoc array containing script variable names as keys and config file
# keywords as values. NOTE: volume= omitted since is has an arg (volname)
declare -A KEYWORDS=([NODES]='nodes=' [BLKDEVS]='blk-devs=' [BRICKMNT]='brick-mnt=' [YARN]='yarn-server=' [MGMT]='hadoop-mgmt-server=' [VOLMNT]='vol-mnt-prefix=')

# parse cmd opts
args="$(getopt -o '' --long $opts -- $@)"
eval set -- "$args" # set up 1st option, if any

while true; do
    # the vars set to true here must match keys in the KEYWORDS assoc array
    case "$1" in
      --nodes)
	NODES=true # else, undefined
        shift
	;;
      --blk-devs)
	BLKDEVS=true # else, undefined
        shift
	;;
      --brick-mnt)
	BRICKMNT=true # else, undefined
        shift
	;;
      --vol-mnt-prefix)
	VOLMNT=true # else, undefined
        shift
	;;
      --yarn-server)
	YARN=true # else, undefined
        shift
	;;
      --hadoop-mgmt-server)
	MGMT=true # else, undefined
        shift
	;;
      --volume)
	VOL=true # else, undefined
	VOLNAME="$2"
	VOL_SECT_LINES=1 # num of line *following* volume=
        shift 2
	;;
      --)
        shift; break
	;;
    esac
done

CONFIG="$1" # config file
[[ ! -e $CONFIG ]] && {
  echo "ERROR: config file \"$CONFIG\" missing";
  exit 1; }

# create tmp file containing all non-blank, non-comment records in the
# the config file
sed '/^ *#/d;/^ *$/d;s/#.*//' $CONFIG >$tmpconf

# for each option specified search for its corresponding key= in the conf file
for opt in ${!KEYWORDS[@]}; do # volume= not in this list
    if [[ -n "${!opt}" ]] ; then # option seen
	kw="${KEYWORDS[$opt]}"
	rtn="$(grep "^$kw" $tmpconf)"
	echo "${rtn#*$kw}"
    fi
done

# now do volume=
[[ -n "$VOL" ]] && {
  rtn="$(grep -A$VOL_SECT_LINES $VOLNAME $tmpconf | \
	tail -n$VOL_SECT_LINES)"; # omit volume name line
  echo "${rtn#*vol-nodes=}"; }

exit 0
