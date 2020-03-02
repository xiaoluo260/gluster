#!/bin/bash


systemctl stop vcfs-flashPlug.service
systemctl disable  vcfs-flashPlug.service

yes | rm -rf /usr/lib/systemd/system/vcfs-flashPlug.service
systemctl daemon-reload

