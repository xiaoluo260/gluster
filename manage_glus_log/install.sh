#!/bin/bash

#glusterfs-logrotate will save 52 logs, we modify to 20, force overwrite

\cp -f glusterfs /etc/logrotate.d/glusterfs

\cp -f glusterfs-georep /etc/logrotate.d/glusterfs-georep
