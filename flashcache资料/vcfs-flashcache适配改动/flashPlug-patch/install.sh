#!/bin/bash

chmod +x *
yes | cp -rf vcfs-flashPlug.service /usr/lib/systemd/system/
systemctl daemon-reload

systemctl enable vcfs-flashPlug.service
systemctl start  vcfs-flashPlug.service



