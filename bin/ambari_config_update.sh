#!/bin/bash
#
# ambari_config_update.sh add/remove value in a property
# Actions (for the passed-in key):
#   add     - add a new key:value to core-site
#   append  - append the new value to the end of the existing value for the
#             passed-in key
#   delete  - delete the passed-in config key[:value]
#   prepend - prepend the new value to the beginning of the existing value for
#             the passed-in key
#   remove  - remove the passed-in value from the key's value
#   replace - replace the existing config value with a new value for the passed-
#             in key.
#
# Syntax: see usage() function.

PREFIX="$(dirname $(readlink -f $0))"

_DEBUG="off"
USERID="admin"
PASSWD="admin"
PROTO='http://'
AMBARI_HOST='localhost'
PROPERTY=''
SITE='core-site'
CONFIG_KEY=''
CONFIG_VALUE=''

# debug: execute cmd in $1 if _DEBUG is set to 'on'.
# Uses globals:
#   _DEBUG
function debug() {
 [ "$_DEBUG" == "on" ] &&  $@
}

# usage: echos general usage paragraph.
function usage() {

  cat <<EOF

Usage: ambari_config_update.sh --configkey <key> [--configvalue <value>] \\
         --action <verb> [-h <ambari_host>] [--config <site-file>] \\
         [-u <user>] [-p <password>] [--port <port>] --cluster <name>

key        : Required. Property key in <site-file>.
value      : Optional. Property value to update <site-file> with. If --action
             is delete no <value> is required (or expected).
verb       : Required. Action to be done to <site-file>. Expected values:
             add|delete|prepend|append|replace|remove.
ambari_host: Optional. Host name for the Ambari server. To use https a url must
             be provided as the host, eg. "https://ambari.vm". Default is
             localhost over http.
site-file  : Optional. Hadoop "site" file. Expect "core-site", "mapred-site",
             or "yarn-site" . Default is "core-site".
user       : Optional. Ambari user. Default is "admin".
password   : Optional. Ambari password. Default is "admin".
port       : Optional. Port number for Ambari server. Default is 8080 for http
             and 8443 for https.
name       : Required. The ambari cluster name.

EOF
  exit 1
}

# parse_cmd: parses the command line via getopt. Returns 1 on errors. Sets the
# following globals:
#   AMBARI_HOST
#   CLUSTER_NAME
#   CONFIG_KEY
#   CONFIG_VALUE
#   _DEBUG
#   DEBUG
#   PASSWD
#   PORT
#   PROPERTY
#   PROTO
#   USERID
function parse_cmd() {

  local errcnt=0
  local OPTIONS='u:p:h:'
  local LONG_OPTS='cluster:,port:,action:,configkey:,configvalue:,config:,debug'

  local args=$(getopt -n "$SCRIPT" -o $OPTIONS --long $LONG_OPTS -- $@)
  (( $? == 0 )) || { echo "$SCRIPT syntax error"; exit -1; }

  eval set -- "$args" # set up $1... positional args

  while true ; do
    case "$1" in
      --debug)
        DEBUG=true; _DEBUG="on"; shift; continue
      ;;
      --port)
        PORT=$2
        shift 2; continue
      ;;
      --cluster)
        CLUSTER_NAME="$2"
        shift 2; continue
       ;;
      --config)
        SITE="$2"
        shift 2; continue
       ;;
      --action)
        ACTION="$2"
        shift 2; continue
       ;;
      --configkey)
        CONFIG_KEY="$2"
        shift 2; continue
       ;;
      --configvalue)
        CONFIG_VALUE="$2"
        shift 2; continue
       ;;
      -u)
        USERID="$2"
        shift 2; continue
      ;;
      -p)
        PASSWD="$2"
        shift 2; continue
      ;;
      -h)
        AMBARI_HOST="$2"
        if [[ "${AMBARI_HOST:0:8}" == 'https://' || \
           "${AMBARI_HOST:0:7}" == 'http://' ]] ; then
          PROTO="${AMBARI_HOST%://*}://"
          AMBARI_HOST="${AMBARI_HOST#*://}" # exclude protocol
        fi
        shift 2; continue
      ;;
      --) # no more args to parse
        shift; break;
      ;;
      *) echo "Error: Unknown option: \"$1\""; return 1
      ;;
    esac
  done

  # missing options/args?
  [[ -z "$CLUSTER_NAME" ]] && {
    echo "Syntax error: cluster name is missing"; ((errcnt++)); }

  if [[ -z "$ACTION" ]] ; then
    echo "Syntax error: ACTION is missing"
    ((errcnt++))
  else
    case "$ACTION" in
	add|append|delete|remove|replace|prepend) # valid
	;;
 	*)
	  echo "Syntax error: unknown action \"$ACTION\""; ((errcnt++))
	;;
    esac
  fi

  [[ -z "$CONFIG_KEY" ]] && {
    echo "Syntax error: <key> is missing"; ((errcnt++)); }

  if [[ -z "$CONFIG_VALUE" ]] ; then
    # error, unless action is delete (need only key)
    [[ "$ACTION" != 'delete' ]] && {
      echo "Syntax error: config <value> is missing"; ((errcnt++)); }
  fi

  (( errcnt > 0 )) && {
    usage; return 1; }

  # set default port
  if [[ -z "$PORT" ]] ; then
    [[ "$PROTO" == 'http://' ]] && PORT=8080 || PORT=8443
  fi

  eval set -- "$@" # move arg pointer so $1 points to next arg past last opt

  [[ $DEBUG == true ]] && debug echo "DEBUGGING ON"
  return 0
}

# removeValue: remove arg2 from the passed-in string, arg1, and output the new
# arg1 string. The arg1 value may be a list of tokens with each token separated
# by a single comma (not space).
# Note: leading, trailing and double commas are also removed from the string 
#   being output.
# Note: implementation does not support blanks within any token value.
# arg1=string from which the arg2 string is removed.
function removeValue() {

  local str="$1"; local rmStr="$2"
  local s; local i=0; local rtn=''

  str=(${str//,/ }) # split into array
  for s in ${str[@]}; do
      if [[ "$s" == "$rmStr" ]] ; then
	unset str[$i] # remove arg2 value from str
      else
	rtn+="$s,"
      fi
      ((i++))
  done

  echo "${rtn%,}" # don't echo trailing comma
}

# doUpdate: updates the PROPERTY in SITETAG. Returns 1 on errors.
# Input: $1 mode; $2 key; $3 value (optional depending on mode)
# Note: the passed-in action (mode) may be changed based on existing settings:
#   'add'     --> 'replace', when prop already exists
#   'append'  --> 'add', when prop does not exist
#   'prepend' --> 'add', when prop does not exist
#   'replace' --> 'add', when prop does not exist
function doUpdate() {

  local mode=$1; local configkey=$2; local configvalue="$3"
  local tmp_cfg="$(mktemp --suffix .$SITE)"
  local old_value; local new_value; local newTag
  local line; local out; local err
  local json_begin="{ \"Clusters\": { \"desired_config\": {\"type\": \"$SITE\", "
  local json_end='}}}'

  debug echo "########## Performing '$mode' $configkey:$configvalue on (Site:$SITE, Tag:$SITETAG)";

  # extract the properties section and write to tmp config file
  curl -k -s -u $USERID:$PASSWD \
   "$AMBARIURL/api/v1/clusters/$CLUSTER_NAME/configurations?type=$SITE&tag=$SITETAG" \
  | sed -n '/\"properties\" :/,/}$/p' >$tmp_cfg # "properties" section
  (( $? != 0 )) || [[ ! -s $tmp_cfg ]] && {
    echo "ERROR: Cannot get $SITE file or file missing all properties";
    return 1; }

  # extract the target key line, if present
  line="$(grep "\"$configkey\" :" $tmp_cfg)"
  line="${line%,}" # remove trailing comma if present
  debug echo "########## LINE = $line"

  # handle missing key in core-site
  # line expected to be non-empty for all modes other than add
  if [[ -z "$line" ]] ; then
    [[ "$mode" == 'delete' || "$mode" == 'remove' ]] && {
      echo "WARN: $configkey not found in $SITE; '$mode' cannot be performed";
      return 0; }
    [[ "$mode" != 'add' ]] && { # append|prepend|replace
      echo "WARN: $configkey missing in $SITE, action changed from '$mode' to 'add'";
      mode='add'; }
  elif [[ "$mode" == 'add' ]] ; then
    echo "WARN: existing \"$configkey\" value in $SITE will be overwritten"
    mode='replace'
  fi

  # extract the unquoted value from line
  if [[ -n "$line" ]] ; then
    old_value="${line#*: }"       # just value portion
    old_value="${old_value//\"/}" # remove all double-quotes
    debug echo "########## current VALUE = $old_value"
  fi

  case "$mode" in
      add) # create new key : value attribute in tmp file
	# add new key:value immediately after properties tag
	sed -i "/\"properties\" : {/a\"$configkey\" : \"$configvalue\",\n" \
	  $tmp_cfg
      ;;
      append)
	# in case configvalue is present in old_value, remove it
	new_value="$(removeValue "$old_value" "$configvalue")"
	[[ -n "$new_value" ]] && new_value+=",$configvalue" ||
	  new_value="$configvalue"
      ;;
      delete) # delete key from tmp file
	sed -i "/\"$configkey\" :/d" $tmp_cfg # inline delete
	# handle case of deleted key was the last line therfore the new last
	# line has a trailing comma which is malformed xml.
        # Note: the eof-1 record is the line to check for a trailing comma.
	local rec="$(wc -l $tmp_cfg)" # eof
	rec=${rec% *} # remove filename
	((rec--)) # 2nd to last line
	sed -i "$rec s/,$//" $tmp_cfg # inline edit
      ;;
      prepend)
	# in case configvalue is present in old_value, remove it
	new_value="$(removeValue "$old_value" "$configvalue")"
	[[ -n "$new_value" ]] && new_value="$configvalue,$new_value" ||
	  new_value="$configvalue"
      ;;
      remove) # remove configvalue from old_value
	# check if configvalue exists
	if [[ ! ",$old_value," =~ ",$configvalue," ]] ; then
	  echo "WARN: $configvalue not present in $configkey; no action needed"
	  return 0 
	fi
	new_value="$(removeValue "$old_value" "$configvalue")"
      ;;
      replace)
	new_value="$configvalue"
      ;;
  esac

  # fix up the "property" section for the PUT below:
  if [[ -n "$new_value" ]] ; then
    [[ "$old_value" == "$new_value" ]] && {
      echo "WARN: no change in '$configkey' value: '$old_value', skipping...";
      return 0; }
    debug echo "########## new config value for $configkey = $new_value"
    # escape / if found in new and/or old values
    [[ "$old_value" =~ '/' ]] && old_value=${old_value//\//\\/}
    [[ "$new_value" =~ '/' ]] && new_value=${new_value//\//\\/}
    sed -i "/$configkey/s/$old_value/$new_value/" $tmp_cfg # inline edit
  fi

  # prepend and append "desired_config" json to config file
  newTag="version$(date '+%s')001"
  json_begin+="\"tag\":\"$newTag\", "
  sed -i "1i $json_begin" $tmp_cfg # prepend json to config file
  echo "$json_end" >>$tmp_cfg
  debug echo "########## new property:"
  debug echo "$(cat $tmp_cfg)"

  # PUT/update the real config(core) file
  out="$(curl -k -s -u $USERID:$PASSWD -X PUT -H 'X-Requested-By:ambari' \
	 $AMBARIURL/api/v1/clusters/$CLUSTER_NAME --data @$tmp_cfg)"
  err=$?
  if (( err != 0 )) || grep -q '"status"' <<<$out ; then
    echo "ERROR: $out"
    return 1
  fi

  sleep 4
  return 0
}

## ** main ** ##

# defaults (global variables)
DEBUG=false
SCRIPT=$0

parse_cmd $@ || exit -1

AMBARIURL="$PROTO$AMBARI_HOST:$PORT"
debug echo "########## AMBARIURL = "$AMBARIURL
debug echo "########## CLUSTER_NAME = $CLUSTER_NAME"

SITETAG="$($PREFIX/find_site_tag.sh core $AMBARIURL $USERID:$PASSWD \
	    "$CLUSTER_NAME")" || {
  echo "ERROR: Cannot get current core-site tag: $SITETAG";
  exit 1; }

doUpdate $ACTION $CONFIG_KEY $CONFIG_VALUE || exit 1

exit 0
