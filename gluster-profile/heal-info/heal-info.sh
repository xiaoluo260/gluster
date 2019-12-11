#!/bin/bash
# heal-info.sh - collect heal data from Gluster about a particular Gluster volume
# usage: 
# bash heal-info.sh your-gluster-volume [output-file]
# output-file is optional, defaults to stdout
# out: need heal file number
# 

#if brick is  down, the heal info is none 
# 尽管13版本有heal info summary选项可以实时关注恢复的对象数目，但是很耗性能，统计一次2：1的纠删，10000个文件 需要2m2.247s
volume_name=$1
RETVAL=0

if [ $# -lt 1 ]  ; then
  echo "usage: heal-info.sh your-gluster-volume"
  exit 1
fi


gluster volume heal $volume_name info summary > /var/tmp/tmp-heal.log

if [ $RETVAL -eq 0 ]; then
  python extract-healinfo.py /var/tmp/tmp-heal.log
fi




