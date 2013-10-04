#!/bin/sh

# here is readahead in KB that we use
# this seems huge but for a modern RAID volume that can do 1 GB/s,
# this is just 65 msec of data, enough to optimize away some seeks on
# a multi-stream workload but not enough to kill response time

tuned_ra=65536
default_ra=128
# we can't do this to LVM block device, only to lowest-layer block device such as /dev/sdb
#tuned_nrq=512
#default_nrq=128

. /etc/tune-profiles/functions

# set readahead in first CLI parameters on ALL Gluster brick devices

OK=0

set_brick_ra() {
  ra=$1
  bricklist='/tmp/local-bricks.list'
  if [ ! -x $gluster_cfg_dir ] ; then return ; fi
  rm -f $bricklist
  touch $bricklist
  ipaddrs="`ifconfig -a | tr ':' ' ' |  awk '/inet addr/ { print $3 }'`"
  for d in `find /var/lib/glusterd/vols -name bricks -type d 2>/tmp/e ` ; do
      (cd $d ; \
          ls | grep `hostname -s` | awk -F: '{ print $2 }' | sed 's/\-/\//g' >> $bricklist ; \
          for ipaddr in $ipaddrs ; do \
          ls | grep $ipaddr | awk -F: '{ print $2 }' | sed 's/\-/\//g' >> $bricklist ; \
          done) 2>> /tmp/bricks.err
  done
  echo -n "setting readahead to $ra on brick devices: "
  for brickdir in `cat $bricklist`  ; do
    # assumption: brick filesystem mountpoint is either the brick directory or parent of the brick directory
    next_dev=`grep " $brickdir " /proc/mounts | awk '{ print $1 }'`
    echo $next_dev
    if [ -z "$next_dev" ] ; then
      brickdir=`dirname $brickdir`
      next_dev=`grep $brickdir /proc/mounts | awk '{ print $1 }'`
    fi
    if [ -z "$next_dev" ] ; then
      echo "ERROR: could not find mountpoint for brick directory $brickdir"
      continue
    fi
    device_path=`readlink $next_dev`
    if [ $? != $OK ] ; then
      # we have to take the raw block device partition number off to get the name in sysfs
      device_path=`echo $next_dev |  sed 's/[0-9]$//'`
    fi
    device_name=`basename $device_path`
    echo -n " $device_name"
    echo $ra > /sys/block/$device_name/queue/read_ahead_kb
  done
  echo
}

start() {
	set_cpu_governor performance

	# Find non-root and non-boot partitions, disable barriers on them
	rootvol=$(df -h / | grep "^/dev" | awk '{print $1}')
	bootvol=$(df -h /boot | grep "^/dev" | awk '{print $1}')
	volumes=$(df -hl --exclude=tmpfs | grep "^/dev" | awk '{print $1}')

	nobarriervols=$(echo "$volumes" | grep -v $rootvol | grep -v $bootvol)
	remount_partitions nobarrier $nobarriervols
        set_brick_ra $tuned_ra
	return 0
}

stop() {

	# Find non-root and non-boot partitions, re-enable barriers
	rootvol=$(df -h / | grep "^/dev" | awk '{print $1}')
	bootvol=$(df -h /boot | grep "^/dev" | awk '{print $1}')
	volumes=$(df -hl --exclude=tmpfs | grep "^/dev" | awk '{print $1}')

	nobarriervols=$(echo "$volumes" | grep -v $rootvol | grep -v $bootvol)
	remount_partitions barrier $nobarriervols
        set_brick_ra $default_ra
	restore_cpu_governor
	return 0
}

process $@
