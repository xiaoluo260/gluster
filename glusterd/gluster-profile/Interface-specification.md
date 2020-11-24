日期  | 版本  | 描述  | 作者|
 
|-----|------|------|-----|

2019-11|V1.0|性能接口说明|张凯敏




#接口说明

---
#主机对外统一提供sh接口，对内业务复杂采用py处理

#优先启动集群profile功能：gluster volume profile volume-name start
---

##客户端带宽/iops接口说明
（gvp-client放在客户端节点任意目录下）

cd gvp-client ; ./gvp-client.sh volume-name client-mountpoint

结果输出在/var/tmp/client-result-$volname: MB_read, MB_write, IOPS_read, IOPS_write




##集群卷带宽/iops接口说明

（gvp-server放在服务端节点任意目录下）

cd gvp-server ; ./gvp-server.sh volume-name

结果输出在/var/tmp/server-result-$volname: MB_read, MB_write, IOPS_read, IOPS_write



##集群容量接口说明

（cluster-capacity放在服务端节点任意目录下）

cd cluster-capacity ; ./cluster-capacity.sh  volume-name

结果输出在/var/tmp/cluster-result-$volname: total_space, free_space



##集群卷恢复进度接口说明
###只显示目前待修复的文件个数，当数值为0，表示全部修复，无异常数据

（heal-info放在服务端节点任意目录下）

cd heal-info ; ./heal-info.sh volume-name

结果输出在/var/tmp/heal-result-$volname: need_heal_file_number


