#!/bin/bash
#
# check_vol_mnt_attrs.sh verifies that the correct mount settings for the
# volume arg have been set on this node. This include verifying both the "live"
# settings, determined by ps, and the "persistent" settings, defined in
# /etc/fstab.

VOLNAME="$1"
errcnt=0

# given the passed-in vol mount opts, verify the correct settings.
function chk_mnt() {

  local opts="$1"
  local errcnt=0

  if ! grep -wq acl <<<$opts; then
    echo "WARN: missing acl mount option"
  fi
  if ! grep -wq "use-readdirp=no" <<<$opts; then
    echo "ERROR: use-readdirp must be set to 'no'"
    ((errcnt++))
  fi
  if ! grep -wq "attribute-timeout=0" <<<$opts; then
    echo "ERROR: attribute-timeout must be set to zero"
    ((errcnt++))
  fi
  if ! grep -wq "entry-timeout=0" <<<$opts; then
    echo "ERROR: entry-timeout must be set to zero"
    ((errcnt++))
  fi
  (( errcnt > 0 )) && return 1 # 1 or more errors
  return 0
}


## live check ##
mntopts="$(ps -ef | grep -w "$VOLNAME" | grep -vwE 'grep|-s')"
mntopts=${mntopts#*glusterfs} # just the opts
out="$(chk_mnt "$mntopts")"
if (( $? != 0 )) ; then
  echo "live check: $out"
  ((errcnt++))
fi

## fstab check ##
cnt=$(grep -c $VOLNAME /etc/fstab)
if (( cnt == 0 )) ; then
  echo "ERROR: $VOLNAME mount missing in /etc/fstab"
  ((errcnt++))
elif (( cnt > 1 )) ; then
  echo "ERROR: $VOLNAME appears more than once in /etc/fstab"
  ((errcnt++))
else # cnt == 1
  mntopts="$(grep -w $VOLNAME /etc/fstab)"
  mntopts=${mntopts#* glusterfs }
  out="$(chk_mnt "$mntopts")"
  if (( $? != 0 )) ; then
    echo "fstab check: $out"
    ((errcnt++))
  fi
fi

(( errcnt > 0 )) && exit 1
exit 0
