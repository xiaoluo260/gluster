#!/bin/bash

#glusterfs-logrotate will save 52 logs, we modify to 20, force overwrite

\cp -f glusterfs /etc/logrotate.d/glusterfs

\cp -f glusterfs-georep /etc/logrotate.d/glusterfs-georep

mkdir -p /opt/manage_glus_log
\cp -f manage_glus_log.sh /opt/manage_glus_log/manage_glus_log.sh
chmod +x /opt/manage_glus_log/manage_glus_log.sh
echo "30 * * * * root /opt/manage_glus_log/manage_glus_log.sh"  >> /etc/crontab
service cron start 
