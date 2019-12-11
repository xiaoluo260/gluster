#!/bin/bash
# cluster-capacity.sh - collect brick data from Gluster about a particular Gluster volume
# usage: 
# bash cluster-capacity.sh your-gluster-volume [output-file]
# output-file is optional, defaults to stdout
# total_space, free_space


volume_name=$1
RETVAL=0

if [ $# -lt 1 ]  ; then
  echo "usage: cluster-capacity.sh your-gluster-volume "
  exit 1
fi


gluster volume status  $volume_name detail > /var/tmp/tmp-capacity.log

if [ $RETVAL -eq 0 ]; then
  python extract-clustercapacity.py /var/tmp/tmp-capacity.log /var/lib/glusterd/vols/dis/info
fi




