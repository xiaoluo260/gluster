#!/bin/bash
cd `dirname $0`
if [ -d "/opt/" ];then
	\cp -rf ../file_life_cycle /opt/
fi
# file_life_cycle.service配置
if [ ! -e "/etc/systemd/system/file_life_cycle.service" ];then
	\cp -f ./script/file_life_cycle.service /etc/systemd/system/
fi
# locate配置
\cp -f ./src/config/updatedb.conf /etc/updatedb.conf
