#!/bin/bash
#
# gen_vol_perf_settings.sh outputs a string which can be used as the value of an
# associative array, meaning "([<key>]='value' ...)" for the gluster settings
# for hadoop volumes.

PREFETCH='performance.stat-prefetch'; PREFETCH_VAL='off'
EAGERLOCK='cluster.eager-lock'	    ; EAGERLOCK_VAL='on'
QUICKREAD='performance.quick-read'  ; QUICKREAD_VAL='off'

echo "([$PREFETCH]='$PREFETCH_VAL' \
 [$EAGERLOCK]='$EAGERLOCK_VAL' \
 [$QUICKREAD]='$QUICKREAD_VAL')"
