#!/bin/bash
#
# vcfs-osdc    Init Script to manage flash-osd loads
#
# chkconfig: 345 98 1
# description: flash-osd Management

# vcfs-osdc options
# modify this before using this init script

RESTART_LOG=/var/log/vcfs/flashPlug.log
CUR_DATE=`date +%Y-%m-%d,%H:%m:%s`


function local_log_file()
{
    echo "${CUR_DATE} vcfs-osdc ""$@" >> ${RESTART_LOG}
    return 0
}
function local_log_info()
{
    local_log_file "[INFO]" "$@"
    return 0
}
function local_log_err()
{
    local_log_file "[ERROR]" "$@"
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

RETVAL=0

#local_log_info "$@"


function flashcache_set_param()
{
    flashcache_name="$1"
    m="$2"
     
    if [ "$m" == "back" ];then  
        /sbin/sysctl -w dev.flashcache.$flashcache_name.fallow_delay=0
        /sbin/sysctl -w dev.flashcache.$flashcache_name.new_style_write_merge=1
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
    return 0
}


# fallow_delay  900 /dev/vdd1 /dev/vdb2 	
function set_fallow_delay()
{
    value=$1
    if [ $1 -lt 0 ]; then
        local_log_err "error $1, fallow_delay  is invalid"
        return 1 
    fi		
    #check ssddev exist
    if [ ! -e $2 ]; then
        #local_log_err "error $2, no ssddev"
        return 2
    fi
    #check dev exist
    if [ ! -e $3 ]; then
        #local_log_err "error $3, no dev "
        return 3
    fi
    ssddev=$2
    dev=$3
    devname=${dev##*/}
    cachedevname=${ssddev##*/}
    flashcache_name="${cachedevname}+${devname}"
    /sbin/sysctl -w dev.flashcache.$flashcache_name.fallow_delay=$value
}
function fallow_delay()
{
    if [ "$MODE" != "back" ]; then
        return 0
    fi
    value=$1
    if [ -z "$value" ]; then
        value=900
    fi
    index=0
    for i in ${SSD_DISK[*]}
    do
        set_fallow_delay $value ${SSD_DISK[${index}]} ${BACKEND_DISK[${index}]} ; RETVAL=$?
        #local_log_info "set_fallow_delay  ${SSD_DISK[${index}]} ${BACKEND_DISK[${index}]} ; RETVAL=$?"
        if [ $RETVAL -ne 0 ]; then
            ret=$RETVAL
            local_log_err "set fallow_delay failed, ret=$RETVAL"
            return $ret
        fi
        index=`expr ${index} + 1`
    done
}
function set_stop_sync()
{
    value=$1
    if [ $1 -lt 0 ]; then
        local_log_err "error $1, stop_sync  is invalid"
        return 1 
    fi		
    #check ssddev exist
    if [ ! -e $2 ]; then
        #local_log_err "error $2, no ssddev"
        return 2
    fi
    #check dev exist
    if [ ! -e $3 ]; then
        #local_log_err "error $3, no dev "
        return 3
    fi
    ssddev=$2
    dev=$3
    devname=${dev##*/}
    cachedevname=${ssddev##*/}
    flashcache_name="${cachedevname}+${devname}"
    /sbin/sysctl -w dev.flashcache.$flashcache_name.stop_sync=$value
}
function stop_sync()
{
    if [ "$MODE" != "back" ]; then
        return 0
    fi
    sync_value=1
    index=0
    for i in ${SSD_DISK[*]}
    do
        set_stop_sync $sync_value ${SSD_DISK[${index}]} ${BACKEND_DISK[${index}]} ; RETVAL=$?
        #local_log_info "set_stop_sync  ${SSD_DISK[${index}]} ${BACKEND_DISK[${index}]} ; RETVAL=$?"
        if [ $RETVAL -ne 0 ]; then
            ret=$RETVAL
            local_log_err "set_stop_sync failed, ret=$RETVAL"
            return $ret
        fi
        index=`expr ${index} + 1`
    done
}
function start_one_osd()
{
    osdid=$1
    ssd=$2
    hdd=$3
    cache_name=$4
    mount_point=$5
    flash_name=$6
	local_log_info "start osd$osdid..."  
    set_noout; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        #return $RETVAL
        local_log_err "Command exec failed, set_noout"
    fi
    
    ret=0
    flashcache_start_osd "${osdid}" "${ssd}"  "${hdd}" "${cache_name}" "${mount_point}"  "${flash_name}"; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        local_log_err "Exec cmd failed, flashcache_start_osd ${osdid} ${ssd}  ${hdd} ${cache_name} ${mount_point}  ${flash_name}" 
        ret=$RETVAL
    fi
    unset_noout; RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        return $RETVAL
    fi

    #lock subsys
    touch $SUBSYS_LOCK
    return $ret
}
#检测异常的缓存设备，停止并重新加载启动,此服务添加到systemd并且循环执行，所以打印均去掉

function restart()
{   
    if [ "$1" == "all" ]; then
        stop
        sleep 1
        start_normal
    else
        recoverd_lock=0
        index1=0
        for i in ${OSD_NUM[*]}
        do
            osd_num=${OSD_NUM[$index1]}
            ssd_dev=${SSD_DISK[$index1]}
            disk_dev=${BACKEND_DISK[$index1]}
            cachedev_name=${CACHEDEV_NAME[$index1]}
            mount_point=${MOUNTPOINT[$index1]}
            flashcache_name=${FLASHCACHE_NAME[$index1]}
            mount_num=`lsblk | grep "osd$i " |wc -l`
            ssduuid_num=`blkid | grep "${ssd_dev##*/}" |wc -l`
            #B020-beta02版本将disk的uuid换成了part-uuid
            diskuuid_num=`blkid | grep "${disk_dev##*/}" |wc -l` 
            if [ $mount_num -lt 2 ]; then
                recoverd_lock=1
                local_log_info "the osd$i need recoverd"
                if [ $ssduuid_num -eq 1 ] && [ $diskuuid_num -eq 1 ]; then
                    stop fast $i ; RETVAL=$?
                    if [ $RETVAL -ne 0 ]; then
                        local_log_err "stop fast $i ; RETVAL=$?"
                        return $RETVAL
                    fi
                    sleep 1
                    start_one_osd "${osd_num}" "${ssd_dev}"  "${disk_dev}" "${cachedev_name}" "${mount_point}"  "${flashcache_name}"; RETVAL=$?
                    if [ $RETVAL -ne 0 ]; then
                        local_log_err "stop fast $i ; RETVAL=$?"
                        return $RETVAL
                    fi	
                else 
                    local_log_info "one of ssd/hdd is down, can't recovering" 
                    return 0
                fi
            fi
            index1=`expr ${index1} + 1`
        done 
        if [ $recoverd_lock -eq 0 ]; then
            return 0
        fi
    fi
}
case $1 in
    restart)
        restart $2
        ;;
    fallow_delay)
        fallow_delay $2
        ;;	
    stop_sync)
        stop_sync
        ;;		
    *)
    local_log_err "Usage: $0 {restart|fallow_delay}"
    exit 1
esac

exit $?
