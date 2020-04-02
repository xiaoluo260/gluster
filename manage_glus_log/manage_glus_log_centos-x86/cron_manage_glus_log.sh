#!/bin/bash

if [ ! -f /etc/logrotate.d/glusterfs ]; then
    \cp -f glusterfs /etc/logrotate.d/glusterfs
fi
if [ ! -f /etc/logrotate.d/glusterfs-georep ]; then
    \cp -f glusterfs-georep /etc/logrotate.d/glusterfs-georep
fi
mkdir -p /opt/manage_glus_log
\cp -f manage_glus_log.sh /opt/manage_glus_log/manage_glus_log.sh
chmod +x /opt/manage_glus_log/manage_glus_log.sh
echo "30 * * * * root /opt/manage_glus_log/manage_glus_log.sh"  >> /etc/crontab
service crond start 
