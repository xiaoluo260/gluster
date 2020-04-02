#!/bin/bash

for file in /var/log/glusterfs/*
do
    if [ -f $file ] && [ ${file##*.} != gz ]; then
        f_size=`ls -l $file | awk '{print $5}'`
        if [ $f_size -gt 104857600 ]; then
            logrotate -vf /etc/logrotate.d/glusterfs
        fi
    fi     
done

for file in /var/log/glusterfs/bricks/*
do
    if [ -f $file ] && [ ${file##*.} != gz ]; then
        f_size=`ls -l $file | awk '{print $5}'`
        if [ $f_size -gt 104857600 ]; then
            logrotate -vf /etc/logrotate.d/glusterfs
        fi
    fi     
done
