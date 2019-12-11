#!/bin/bash
# gvp-server.sh - collect performance data from Gluster about a particular Gluster volume
# usage: 
# bash gvp-server.sh your-gluster-volume 
# 
#defaults to stdout:
# MB_read, MB_write, IOPS_read, IOPS_write

volume_name=$1
RETVAL=0
if [ $# -lt 1 ]  ; then
  echo "usage: gvp-server.sh your-gluster-volume "
  exit 1
fi


sample_interval=1

# start up profiling

gluster volume profile $volume_name info clear > /tmp/past

gluster volume profile $volume_name info > /tmp/past


# generate samples  

sleep $sample_interval
gluster volume profile $volume_name info > /var/tmp/tmp-server.log ;RETVAL=$?
if [ $RETVAL -eq 0 ]; then
  python extract-glvolprof.py /var/tmp/tmp-server.log
fi

 

