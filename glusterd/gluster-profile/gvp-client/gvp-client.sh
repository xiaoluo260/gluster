#!/bin/bash
# gvp-client.sh - collect perf data from Gluster for client's usage 
# of Gluster volume from 1 mountpoint
#
# ASSUMPTION: "gluster volume profile your-volume start" has already happened
#
# usage: 
#  chmod u+x gvp-client.sh
#  ./gvp-client.sh your-gluster-volume your-client-mountpoint 
#  bytes_read, bytes_written, read_iops, write_iops
volume_name=$1
mountpoint=$2
outputfile=/var/tmp/client-result-${volume_name}

RETVAL=0

if [ $# -lt 2 ]  ; then
  echo "usage: gvp-client.sh your-gluster-volume your-client-mountpoint"
  exit 1
fi

sample_cmd="setfattr -n trusted.io-stats-dump -v "

sample_interval=1

#timestamp=`date +%Y-%m-%d-%H-%M`


# so next sample interval will be $sample_interval
$sample_cmd /var/tmp/tmp-client.log $mountpoint

sleep $sample_interval
rm -f /var/tmp/tmp-client.log.$volume_name
$sample_cmd /var/tmp/tmp-client.log $mountpoint ; RETVAL=$?
if [ $RETVAL -eq 0 ]; then
  python extract-gl-client-prof.py /var/tmp/tmp-client.log.$volume_name $outputfile
fi


