#!/bin/bash
RESTART_LOG=/var/log/vcfs/flashPlug.log
mkdir /var/log/vcfs -p
if [ ! -e $RESTART_LOG ]; then
    touch $RESTART_LOG
fi

FILE_SIZE=`du -b $RESTART_LOG | awk '{print $1}'`
#大于1G则清空
if [ $FILE_SIZE -gt 1073741824 ]; then
    echo "" > $RESTART_LOG
fi	
while true
do
    sh /opt/vcfs/vcfs-flashPlug/vcfs-flashosdc.sh restart
    sleep 10
done
	

