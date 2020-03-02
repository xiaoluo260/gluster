#!/bin/bash
#
# vcfs-osdc    Init Script to manage vcfs-osdc loads
#
# chkconfig: 345 98 1
# description: vcfs-osdc Management

# vcfs-osdc options
# modify this before using this init script

function local_log()
{
    echo "vcfs-osdc ""$@"
    logger -t vcfs-osdc "$@"
    return 0
}

function local_log_info()
{
    local_log "[INFO]" "$@"
    return 0
}
function local_log_err()
{
    local_log "[ERROR]" "$@"
    return 0
}

function set_noout()
{
    vcfs osd set noout; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "Command exec first failed：vcfs osd set noout, ret=$RETVAL"
        #return $RETVAL
        sleep 1
        vcfs osd set noout; RETVAL=$?
        if [ $RETVAL -ne 0 ]; then
            local_log_err "Command exec second failed：vcfs osd set noout, ret=$RETVAL"
            return $RETVAL
        fi
    fi
    
    return 0
}
function unset_noout()
{
    vcfs osd unset noout; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "Command exec failed：vcfs osd unset noout, ret=$RETVAL"
        return $RETVAL
    fi
    return 0
}

function test_and_wait_dev()
{
    dev=$1
    wt=$2
    twt=$(($wt*2))
    i=0
    while [ -n "$dev" ] && [ $i -le $twt ]; do
        if [  -L "$dev" ]; then 
            return 0
        else
            usleep 500000                ##0.5s
            i=$(($i+1))
        fi
    done
    local_log_err "Device ($dev) not exist in the system, wait $wt timeout"
    return 1
}

##########################################################################################

DEFAULT_MODE=around
DEFAULT_RETRY=5

if [ ! -f /etc/vcfs/vcfs-osdc.conf ]; then
    touch /etc/vcfs/vcfs-osdc.conf
fi

if [ ! -f /etc/vcfs/vcfs-osdc-mode ]; then
    echo "$DEFAULT_MODE" > /etc/vcfs/vcfs-osdc-mode
fi

OSD_NUM=(`cat /etc/vcfs/vcfs-osdc.conf|awk '{print $1}'`)
SSD_DISK=(`cat /etc/vcfs/vcfs-osdc.conf|awk '{print $2}'`)
BACKEND_DISK=(`cat /etc/vcfs/vcfs-osdc.conf|awk '{print $3}'`)
CACHEDEV_NAME=(`cat /etc/vcfs/vcfs-osdc.conf|awk '{print $4}'`)
MOUNTPOINT=(`cat /etc/vcfs/vcfs-osdc.conf|awk '{print $5}'`)
FLASHCACHE_NAME=(`cat /etc/vcfs/vcfs-osdc.conf|awk '{print $6}'`)
JOURNAL=(`cat /etc/vcfs/vcfs-osdc.conf|awk '{print $7}'`)
NUM=${#SSD_DISK[*]}
MODE=`cat /etc/vcfs/vcfs-osdc-mode`


#globals
DMSETUP=`/usr/bin/which dmsetup`
SERVICE=vcfs-osdc
FLASHCACHE_LOAD=/sbin/flashcache_load
SUBSYS_LOCK=/var/lock/subsys/$SERVICE
ENABLE_FLAG=/etc/vcfs/vcfs-osdc
FLASH_SERV=/opt/vcfs/vcfs-flashPlug

RETVAL=0

local_log_info "$@"

function flash_serv_load()
{
    cd $FLASH_SERV
    sh install.sh
    RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "Failed: flashcache_serv install failed"
        return $RETVAL
    fi
}
function flash_serv_unload()
{
    cd $FLASH_SERV
    sh uninstall.sh
    if [ $RETVAL -ne 0 ]; then
        local_log_err "Failed: flashcache_serv uninstall failed"
        return $RETVAL
    fi
}

function flashcache_set_param()
{
    flashcache_name="$1"
    m="$2"
     
    if [ "$m" == "back" ];then 
        #/sbin/sysctl -w dev.flashcache.$flashcache_name.new_style_write_merge=1
        /sbin/sysctl -w dev.flashcache.$flashcache_name.fallow_delay=0
        /sbin/sysctl -w dev.flashcache.$flashcache_name.new_style_write_merge=0
    fi
    #/sbin/sysctl -w dev.flashcache.$flashcache_name.reclaim_policy=1  
    #/sbin/sysctl -w dev.flashcache.$flashcache_name.skip_seq_thresh_kb=512
    return 0
}

function get_mode()
{
    cat /etc/vcfs/vcfs-osdc-mode
}


function stop_osd_retry()
{
    osdid=$1
    retry=$2
    
    t=0
    if [ -z "$retry" ]; then
        retry=$DEFAULT_RETRY
    fi
    
    while [ $t -lt $retry ]; do
        systemctl reset-failed vcfs-osd@$osdid >/dev/null 2>&1
        systemctl stop vcfs-osd@$osdid; RETVAL=$?
        if [ $RETVAL -eq 0 ]; then
            break;
        else
            count=`systemctl status vcfs-osd@$osdid | grep "Active: active" | wc -l`
            if [ $count -gt 0 ] && [ $t -le $retry ]; then
                local_log_err "systemctl stop osd.$osdid failed, retry $t"
            fi
            t=$(($t+1))
        fi
    done    
    return $RETVAL
}


function osd_mount_start()
{
    osdid="$1"
    cachedev_name="$2"
    mountpoint="$3"
    flashcache_name="$4"
    
    if [ ! -L /dev/mapper/$cachedev_name ]; then
        local_log_err "Not Found: /dev/mapper/$cachedev_name"
        return 1
    fi
    
    #mount
    /bin/mount /dev/mapper/$cachedev_name $mountpoint -o noatime
    RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "Mount Failed: /dev/mapper/$cachedev_name to $mountpoint" 
        return $RETVAL
    fi
    local_log_info "Start vcfs-osd@$osdid..." 
    systemctl reset-failed vcfs-osd@$osdid
    systemctl start vcfs-osd@$osdid; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "start vcfs-osd@$osdid failed . Exited with status - $RETVAL"
        return $RETVAL
    fi
    local_log_info "Start vcfs-osd@$osdid success"
    return $RETVAL
}

function flashcache_start_osd()
{
    osdid="$1"            ##x
    ssd_disk="$2"         ##/dev/disk/by-uuid/xxx-xxx-xxx 
    backend_dev="$3"
    cachedev_name="$4"    ##osdx
    mountpoint="$5"       ##/var/lib/vcfs/osd/vcfs-osdx
    flashcache_name="$6"  ##很长的串
    
    test_and_wait_dev "$ssd_disk" 120; RETVAL=$?
    if [  $RETVAL -ne 0 ]; then 
        local_log_err "Wait ssd $ssd_disk 120 timeout, exit"
        return $RETVAL
    fi
    
    /bin/umount "$mountpoint" 2>/dev/null
    #flashcache_load the cachedev
    local_log_info "Load vcfs-osd@$osdid flashcache start"
    
    if [ "$MODE" == "back" ]; then
        $FLASHCACHE_LOAD "$ssd_disk" "$cachedev_name"
        RETVAL=$?
        if [ $RETVAL -ne 0 ]; then
            local_log_err "Failed: flashcache_load $ssd_disk $cachedev_name"
            return $RETVAL
        fi
    else
        flashcache_create -p $MODE osd$osdid "$ssd_disk" "$backend_dev" ; RETVAL=$?
        local_log_info "flashcache_create -p $MODE osd$osdid $ssd_disk $backend_dev, ret=$RETVAL"
        if [ $RETVAL -ne 0 ]; then
            local_log_err "flashcache_create failed, ret=$RETVAL"
            return $RETVAL
        fi
    fi
    local_log_info "Load vcfs-osd@$osdid flashcache finish"
    flashcache_set_param $flashcache_name "$MODE"
    osd_mount_start "$osdid" "$cachedev_name"  "$mountpoint" "flashcache_name";RETVAL=$?
    return $RETVAL
}

function start_normal()
{
    local_log_info "vcfs-osdc start..."
    
    #Load the module
    /sbin/modprobe flashcache; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "Module Load Error: flashcache. Exited with status - $RETVAL"
        return $RETVAL
    fi
    
    set_noout; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        #return $RETVAL
        local_log_err "Command exec failed, set_noout"
    fi
    
    index=0
    local_log_info "Starting vcfs-osdc..." 
    ret=0
    for i in ${SSD_DISK[*]}  
    do
        flashcache_start_osd "${OSD_NUM[${index}]}" "${SSD_DISK[$index]}"  "${BACKEND_DISK[${index}]}" "${CACHEDEV_NAME[${index}]}" "${MOUNTPOINT[${index}]}"  "${FLASHCACHE_NAME[${index}]}"; RETVAL=$?
        if [ $RETVAL -ne 0 ]; then
            local_log_err "Exec cmd failed, flashcache_start_osd ${OSD_NUM[${index}]} ${SSD_DISK[$index]}  ${BACKEND_DISK[${index}]} ${CACHEDEV_NAME[${index}]} ${MOUNTPOINT[${index}]}  ${FLASHCACHE_NAME[${index}]}" 
            ret=$RETVAL
        fi
        index=`expr ${index} + 1`
    done
    
    unset_noout; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        return $RETVAL
    fi

    #lock subsys
    touch $SUBSYS_LOCK
    return $ret
}



function change_mode()
{
    nmode="$1"
    oldmode="$MODE"
    if [ "$nmode" == "$MODE" ];then
        local_log_info "Flashcache mode aleady be $MODE, do nothing"
        return 0
    fi
    #zkm add for hot-swap check flash-dev
    systemctl stop vcfs-flashPlug.service
    ##slow stop osd
    stop slow; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "Slow stop failed, ret=$RETVAL"
        return $RETVAL
    fi
    
    set_noout; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        #return $RETVAL
        local_log_err "Command exec failed, set_noout"
    fi
    
    ret=0
    index=0
    for i in ${SSD_DISK[*]}
    do
        /bin/umount ${MOUNTPOINT[${index}]} 
        flashcache_create -p $nmode osd${OSD_NUM[${index}]} ${SSD_DISK[${index}]} ${BACKEND_DISK[${index}]} ; RETVAL=$?
        local_log_info "create -p $nmode osd${OSD_NUM[${index}]} ${SSD_DISK[${index}]} ${BACKEND_DISK[${index}]}, ret=$RETVAL"
        if [ $RETVAL -ne 0 ]; then
            ret=$RETVAL
            local_log_err "flashcache_create failed, ret=$RETVAL"
            unset_noout
            return $ret
        fi
        index=`expr ${index} + 1`
    done
    
    index=0
    for i in ${SSD_DISK[*]}
    do
        flashcache_set_param $flashcache_name "$nmode"
        osd_mount_start "${OSD_NUM[${index}]}" "${CACHEDEV_NAME[${index}]}" "${MOUNTPOINT[${index}]}"  "${FLASHCACHE_NAME[${index}]}"; RETVAL=$?
        if [ $RETVAL -ne 0 ]; then
            ret=$RETVAL
            local_log_err "Function osd_mount_start exec failed"
        fi  
        index=`expr ${index} + 1`
    done
    
    if [ $ret -eq 0 ]; then
         ##record new mode
        echo "$nmode" > /etc/vcfs/vcfs-osdc-mode
        MODE="$nmode"
    fi
    unset_noout
    local_log_info "Flashcache change mode from ($oldmode) to ($nmode), ret=$ret"
    #zkm add for hot-swap check flash-dev
    systemctl start vcfs-flashPlug.service
    return $ret

}



function stop_flashcache_osd()
{
    sflag="$1"
    osdid="$2"
    ssd_dev="$3"
    backend_dev="$4"
    cache_dev="$5" 
    mount_point="$6"
    flashcache_name="$7"
    
    local_log_info "Begin stop flashcache for osd$osdid"
    stop_osd_retry $osdid $DEFAULT_RETRY; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        return $RETVAL
    fi
    
    #check for slow flag
    if [ "$sflag" == 'slow' ]; then
        FLAG=0
    else
        FLAG=1
    fi
    if [ "$MODE" == "back" ]; then
        ##only back mode we set  fast_remove
        /sbin/sysctl -w dev.flashcache.$flashcache_name.fast_remove=$FLAG 
    fi
      
    local_log_info "Start Flushing vcfs-osdc: Flushes to $backend_dev"
    #unmount
    /bin/umount $mount_point
    
    info=`$DMSETUP remove $cache_dev 2>&1`; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        count=`echo "$info" | grep "No such device or address" | wc -l`
        if [ $count -gt 0 ]; then
            RETVAL=0
        else
            #try again
            sleep 5
            info=`$DMSETUP remove $cache_dev 2>&1`; RETVAL=$?
        fi
    fi
    local_log_info "End Flushing $backend_dev,result=$RETVAL" 
    
    if [ "$sflag" == "slow" ]; then
        flashcache_destroy $ssd_dev
    fi
    local_log_info "Finish stop $ssd_dev"
    return $RETVAL
}

function stop() {

    flag="$1"
    osdid="$2"
    if [ -z "$flag" ]; then
        flag="normal"
    fi
    
    set_noout; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        #return 1
        local_log_err "Command exec failed, set_noout"
    fi
    
    local_log_info "Stopping vcfs-osdc..." 
    #check conf exist osdid
    temposdid=10000
    for i in ${OSD_NUM[*]}
    do
        if [[ "$osdid" == $i ]]; then
            local_log_info "found $osdid, osd$osdid has exist in the conf"
            temposdid=$i
            break
        fi
    done
    
    ret=0
    index=0
    for i in ${SSD_DISK[*]}
    do
        if [ ${temposdid} != 10000 ]; then
            if [ ${temposdid} != ${OSD_NUM[${index}]} ]; then
                index=`expr ${index} + 1`
                continue
            fi
        fi
        stop_flashcache_osd "$flag" "${OSD_NUM[${index}]}" "${SSD_DISK[${index}]}" "${BACKEND_DISK[${index}]}" "${CACHEDEV_NAME[${index}]}" "${MOUNTPOINT[${index}]}" "${FLASHCACHE_NAME[${index}]}"
        RETVAL=$?
        if [ $RETVAL -ne 0 ]; then 
            local_log_err "stop_flashcache_osd failed, osd id ${OSD_NUM[${index}]}"
            ret=$RETVAL
        fi
        index=`expr ${index} + 1`
    done
    
    unset_noout; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        return $RETVAL
    fi
    
    #unlock subsys
    rm -f $SUBSYS_LOCK
    return $ret
}

function status() {
    [ -f $SUBSYS_LOCK ] && echo "vcfs-osdc status: loaded" || echo "vcfs-osdc status: NOT loaded";
    index=0
    for i in ${SSD_DISK[*]}
    do
        $DMSETUP status ${CACHEDEV_NAME[${index}]}

        local_log_info "SSD_DISK${index}=${SSD_DISK[index]},result=$?"

        index=`expr ${index} + 1`
    done
}

function enable() {
    [ -f $SUBSYS_LOCK ] && echo "vcfs-osdc enable: loaded" || echo "vcfs-osdc enable: NOT loaded";
    if [ -f $ENABLE_FLAG ]; then
        local_log_info "vcfs-osdc enable: enabled,do nothing." 
        chkconfig vcfs-osdc on
    else
        touch $ENABLE_FLAG
        local_log_info "vcfs-osdc enable: enabled." 
        chkconfig vcfs-osdc on
    #sed -i '/vcfs-/s/^/#&/' /etc/fstab
    fi
    
    systemctl enable vcfs-fhotagent.service
    systemctl start vcfs-fhotagent.service
    sed -i '/fs.file-max = 16777216/d' /etc/sysctl.conf
    sed -i '/fs.file-max = 16777217/d' /etc/sysctl.conf
    #echo "fs.file-max = 16777217" >> /etc/sysctl.conf
    echo "fs.file-max = 16777216" >> /etc/sysctl.conf
    sysctl -p
    return 0
}

function disable() {
    [ -f $SUBSYS_LOCK ] && echo "vcfs-osdc disable: loaded" || echo "vcfs-osdc disable: NOT loaded";
    local_log_info "vcfs-osdc disable: disabled." 
    chkconfig vcfs-osdc off
    if [ -f $ENABLE_FLAG ]; then
        rm -f $ENABLE_FLAG
        #sed -i '/vcfs-/s/^#//' /etc/fstab
    fi
    
    #kill -9 $(pidof fhotagent)
    systemctl disable vcfs-fhotagent.service
    systemctl stop vcfs-fhotagent.service
    sed -i '/fs.file-max = 16777216/d' /etc/sysctl.conf
    sed -i '/fs.file-max = 16777217/d' /etc/sysctl.conf
    echo "fs.file-max = 16777216" >> /etc/sysctl.conf
    sysctl -p
    return 0
     
}

#vcfs-osdc create 0 /dev/vdd1 /dev/vdb2 /dev/vdd2
function create() {
    #check parm
    #if [ $# != 5 ]; then
    #    echo error parameters
    #    exit 1
    #fi

    #check ssddev exist
    if [ ! -e $3 ]; then
         local_log_err "error $3, no ssddev"
         return 2
    fi
    #check dev exist
    if [ ! -e $4 ]; then
         local_log_err "error $4, no dev "
         return 3
    fi 
     #check conf exist
    for i in ${OSD_NUM[*]}
    do
        if [ $2 == i ]; then
            local_log_err "error $2, osd$2 has exist in the conf"
            return 4
        fi
    done
    
    #get input data
    osdid=$2
    ssddev=$3
    dev=$4
    dir=/var/lib/vcfs/osd/vcfs-${osdid}
    devname=${dev##*/}
    cachedevname=${ssddev##*/}

    journal=null
    if [ -e $5 ]; then
         journal=$5
    fi

    #do work
    set_noout; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        #return 5
        local_log_err "Command exec failed, set_noout"
    fi
    
    stop_osd_retry $osdid $DEFAULT_RETRY; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        unset_noout
        return 5
    fi

    vcfs-osd --flush-journal -i ${osdid} --cluster vcfs 
    \cp -an /var/lib/vcfs/osd/vcfs-${osdid}/journal /var/lib/vcfs/osd/vcfs-${osdid}/journal-bak
    rm /var/lib/vcfs/osd/vcfs-${osdid}/journal -f
    vcfs-osd --mkjournal -i ${osdid} --cluster vcfs --setuser vcfs --setgroup vcfs
    umount ${dir}; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "umount $dir failed, ret $RETVAL"
        systemctl start vcfs-osd@${osdid}
        unset_noout
        return 6
    fi
    
    flashcache_destroy -f ${ssddev} 
    local_log_info "flashcache_create -p $MODE osd${osdid} ${ssddev} ${dev}"
    info=`flashcache_create -p $MODE osd${osdid} ${ssddev} ${dev} 2>&1` 
    RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "flashcache_create -p $MODE osd${osdid} ${ssddev} ${dev}"
        local_log_err "flashcache_create failed, ret $RETVAL"
        echo "$info" >>/var/log/vcfs/vcfs-osdc.log
        mount ${dev} ${dir} -o noatime
        systemctl start vcfs-osd@${osdid}
        unset_noout
        return 7
    fi
    
    flashcache_set_param "${cachedevname}+${devname}"
 
    #modify conf
    confline=`sed -n "/\[osd.${osdid}\]/=" /etc/vcfs/vcfs.conf` || { local_log_err "command failed, modify config"; }
    confline=`expr ${confline} + 2`
    newdev=/dev/mapper/osd${osdid}
    #sed -i "${confline}s/${devlist[${index}]}/${newdev}/g" /etc/vcfs/vcfs.conf    ---var has / code
    sed -i "/osd${osdid} \/var/d" /etc/vcfs/vcfs-osdc.conf
    sed -i "${confline}s#${dev}#${newdev}#g" /etc/vcfs/vcfs.conf || { local_log_err "command failed, modify config"; }
    sed -i "/vcfs-${osdid} /s/^/#&/" /etc/fstab
     
    mount ${newdev} ${dir} -o noatime 
    RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "mount command failed (${newdev} ${dir} -o noatime)"
        unset_noout
        return 8
    fi
   
    systemctl reset-failed vcfs-osd@${osdid}
    systemctl start vcfs-osd@${osdid} 
    RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "start vcfs-osd@${osdid} failed . Exited with status - $RETVAL"
        unset_noout
        return 9
    fi
    
    systemctl disable vcfs-osd@${osdid}
    chkconfig vcfs-osdc on
    systemctl enable vcfs-fhotagent.service
    systemctl start vcfs-fhotagent.service
    sed -i '/fs.file-max = 16777216/d' /etc/sysctl.conf
    sed -i '/fs.file-max = 16777217/d' /etc/sysctl.conf
    #echo "fs.file-max = 16777217" >> /etc/sysctl.conf
    echo "fs.file-max = 16777216" >> /etc/sysctl.conf
    sysctl -p
    unset_noout
    
    #0 /dev/vdd1 /dev/vdb2 osd0 /var/lib/vcfs/osd/vcfs-0 vdd1+vdb2/usr/lib/udev/rules.d/95-vcfs-osd.rules
    echo "${osdid} ${ssddev} ${dev} osd${osdid} /var/lib/vcfs/osd/vcfs-${osdid} ${cachedevname}+${devname} ${journal}" >> /etc/vcfs/vcfs-osdc.conf
    sed -i "/${cachedevname}/d"  /usr/lib/udev/rules.d/95-vcfs-osd.rules
    sed -i "/${devname}/d"  /usr/lib/udev/rules.d/95-vcfs-osd.rules
    echo "ACTION==\"add\" SUBSYSTEM==\"block\", ENV{DEVTYPE}==\"partition\", ENV{ID_PART_ENTRY_UUID}==\"${cachedevname}\", RUN+=\"/usr/sbin/flash.sh add ${cachedevname} ${devname} ${osdid}\"" >> /usr/lib/udev/rules.d/95-vcfs-osd.rules
    echo "ACTION==\"remove\" SUBSYSTEM==\"block\", ENV{DEVTYPE}==\"partition\", ENV{ID_PART_ENTRY_UUID}==\"${cachedevname}\", RUN+=\"/usr/sbin/flash.sh remove ${cachedevname} ${devname} ${osdid}\"" >> /usr/lib/udev/rules.d/95-vcfs-osd.rules
    echo "ACTION==\"add\" SUBSYSTEM==\"block\", ENV{DEVTYPE}==\"partition\", ENV{ID_PART_ENTRY_UUID}==\"${devname}\", RUN+=\"/usr/sbin/flash.sh add ${cachedevname} ${devname} ${osdid}\"" >> /usr/lib/udev/rules.d/95-vcfs-osd.rules
    echo "ACTION==\"remove\" SUBSYSTEM==\"block\", ENV{DEVTYPE}==\"partition\", ENV{ID_PART_ENTRY_UUID}==\"${devname}\", RUN+=\"/usr/sbin/flash.sh remove ${cachedevname} ${devname} ${osdid}\"" >> /usr/lib/udev/rules.d/95-vcfs-osd.rules
    systemctl restart systemd-udevd
    local_log_info "config flashcache success, osd.${osdid}"
    #zkm add for hot-swap check flash-dev
    flash_serv_load
    return 0
}

#vcfs-osdc remove 0 /dev/vdd1 /dev/vdb2
function remove() {
    #check parm
    if [ $# != 4 ]; then
        local_log_err "error parameters"
        return 1
    fi
    
    #check ssddev exist
    if [ ! -e $3 ]; then
        local_log_err "error $3, no ssddev "
        return 2
    fi
    
    #check dev exist
    if [ ! -e $4 ]; then
        local_log_err "error $4, no dev "
        return 3
    fi

    #check conf exist
    tempparm=0
    for i in ${OSD_NUM[*]}
    do
        if [ $2 == ${i} ]; then
            tempparm=1
        fi
    done
    if [ ${tempparm} != 1 ]; then
        local_log_err "osd not in conf"
        exit 4
    fi
    #zkm add for hot-swap check flash-dev
    systemctl stop vcfs-flashPlug.service
	
    #get input data
    osdid=$2
    ssddev=$3
    dev=$4
    dir=/var/lib/vcfs/osd/vcfs-${osdid}
    devname=${dev##*/}
    cachedevname=${ssddev##*/}
    
    journal=null
    if [ -e $5 ]; then
         journal=$5
    fi
 
    #do work
    set_noout; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        #return 5
        local_log_err "Command exec failed, set_noout"
    fi
    
    stop_osd_retry ${osdid} $DEFAULT_RETRY; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        unset_noout
        return 6
    fi
    #if [ "${journal}" != 'null' ]; then
    #  vcfs-osd --flush-journal -i ${osdid} --cluster vcfs 
    #  \cp -a /var/lib/vcfs/osd/vcfs-${osdid}/journal-bak /var/lib/vcfs/osd/vcfs-${osdid}/journal
    #  vcfs-osd --mkjournal -i ${osdid} --cluster vcfs
    #fi
    umount ${dir}; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "Command exec failed, umount ${dir}, ret=$RETVAL"
        unset_noout
        return 7
    fi
    
    local_log_info "Begin remove osd${osdid} flashcache"
    dmsetup remove osd${osdid}; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "Command exec failed, dmsetup remove osd${osdid}, ret=$RETVAL"
        unset_noout
        return 8
    fi
    local_log_info "End remove osd${osdid} flashcache"
     
    #modify conf
    confline=`sed -n "/osd.${osdid}/=" /etc/vcfs/vcfs.conf`; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "Modify vcfs.conf failed, ret=$RETVAL"
    fi
    confline=`expr ${confline} + 2`
    newdev=/dev/mapper/osd${osdid}

    sed -i "${confline}s#${newdev}#${dev}#g" /etc/vcfs/vcfs.conf || { echo "command failed"; }
    sed -i "/vcfs-${osdid} /s/^#//" /etc/fstab
     
    mount ${dev} ${dir} -o noatime; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "Command exec failed, mount ${dev} ${dir} -o noatime, ret=$RETVAL"
        unset_noout
        return 9
    fi

    systemctl reset-failed vcfs-osd@${osdid}
    systemctl start vcfs-osd@${osdid}; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "start vcfs-osd@${osdid} failed . Exited with status - $RETVAL"
        unset_noout
        return 10
    fi

    systemctl enable vcfs-osd@${osdid}
    RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "enable vcfs-osd@${osdid} failed . Exited with status - $RETVAL" 
        unset_noout
        return 11
    fi

    unset_noout
    #0 /dev/vdd1 /dev/vdb2 osd0 /var/lib/vcfs/osd/vcfs-0 vdd1+vdb2
    sed -i "/^${osdid} /d" /etc/vcfs/vcfs-osdc.conf
    if [ ! -s /etc/vcfs/vcfs-osdc.conf ]; then
        local_log_info "vcfs-osdc-mode is removed for init mode."
        rm /etc/vcfs/vcfs-osdc-mode -f
    fi
    sed -i "/${cachedevname}/d"  /usr/lib/udev/rules.d/95-vcfs-osd.rules
    sed -i "/${devname}/d"  /usr/lib/udev/rules.d/95-vcfs-osd.rules
    systemctl restart systemd-udevd
    #zkm add for hot-swap check flash-dev	
    if [ ! -a /etc/vcfs/vcfs-osdc-mode ]; then
        flash_serv_unload
    else
        systemctl start vcfs-flashPlug.service
    fi 	
    return 0
}

function getupath(){
    local bpath=$1
    local bname=${bpath##*/}
    local bdname=`echo ${bname}|cut -c1-3`     
    local buuid=`ls -l /dev/disk/by-partuuid/|grep -w $bname|awk '{print $9}'`
    local buuidpath=/dev/disk/by-partuuid/${buuid}
    echo ${buuidpath}
}


#vcfs-osdc autogen /dev/sdb 1
function autogen() {
    #check cdev exist
    if [ ! -e $1 ]; then
        local_log_err "error $1, no cdev "
        return 2
    fi
    local cdev=$1
    local osdnums=$2
    local jsize=6

    #mkpart
    start=0
    end=${jsize}
    parted -s $cdev mklabel gpt
    for ((i=1;i<=$osdnums;i++))
    do
        parted -s $cdev mkpart primary ${start}G ${end}G
        start=`expr ${start} + ${jsize}`
        end=`expr ${end} + ${jsize}`
    done
    seg=`expr 100 / $osdnums`
    parted -s $cdev mkpart primary ${start}G ${seg}%
    
    start=${seg}
    end=`expr ${start} + ${seg}`
    for ((i=2;i<=$osdnums;i++))
    do
        parted -s $cdev mkpart primary ${start}% ${end}%
        start=`expr ${start} + ${seg}`
        end=`expr ${end} + ${seg}`
    done
    sleep 5
    
    #make cache
    osdlist=(`mount|grep '/vcfs-'|grep '/sd'|awk '{print $3}'|awk -F '-' '{print $2}'`)
    index=1
    sindex=`expr ${osdnums} + 1`
    for autogen_i in ${osdlist[*]}  
    do
        bpath=`mount|grep "vcfs-${autogen_i} "|awk '{print $1}'`
        bupath=`getupath ${bpath}`
        cupath=`getupath ${cdev}${sindex}`
        MODE="back"
        create "create" "${autogen_i}" "${cupath}" "${bupath}" 
        
        #make journal
        jupath=`getupath ${cdev}${index}`
        systemctl stop vcfs-osd@${autogen_i}
        \cp -an /var/lib/vcfs/osd/vcfs-${autogen_i}/journal /var/lib/vcfs/osd/vcfs-${autogen_i}/journal-bak
        rm /var/lib/vcfs/osd/vcfs-${autogen_i}/journal -f
        ln -s ${jupath} /var/lib/vcfs/osd/vcfs-${autogen_i}/journal
        chown -R vcfs:vcfs /var/lib/vcfs/osd/vcfs-${autogen_i}/journal 
        chown -R vcfs:vcfs ${jupath}
        vcfs-osd -i ${autogen_i} --mkjournal
        systemctl reset-failed vcfs-osd@${autogen_i}
        systemctl restart vcfs-osd@${autogen_i}
        
        if [ "${index}" == "${osdnums}" ];then
            break
        fi
        index=`expr ${index} + 1`
        sindex=`expr ${sindex} + 1`
    done 
    
}

case $1 in
    create)
        create $1 $2 $3 $4 $5
        ;;
    remove)
        remove $1 $2 $3 $4 $5
        ;;
    start)
        start_normal
        ;;
    stop)
        stop
        ;;
    enable)
        enable
        ;;
    disable)
        disable
        ;;
    status)
        status
        ;;
    backmode)
        change_mode back
        ;;
    thrumode)
        change_mode thru
        ;;
    aroundmode)
        change_mode around
        ;;
    slowstop)
        stop slow $2
        ;;
    get_mode)
        get_mode
        ;;
    autogen)
        autogen $2 $3
        ;;
    *)
    echo "Usage: $0 {start|stop|status|backmode|thrumode|aroundmode|get_mode|enable|disable}"
    exit 1
esac

exit $?
