# -*- coding: utf-8 -*-
import os
import time
import subprocess
from config.logconfig import notifier_logger as logger
from config.config import FILE_LIFE_MOUNT_DIR
from file_io import update_policy


def exec_cmd(cmd, timeout=8):
    """
    :param cmd: 需要执行的命令
    :param timeout -1 代表不限制超时时间
    执行系统命令
    :return:
    """
    if timeout != -1:
        cmd = 'timeout {} {}'.format(timeout, cmd)
    ret = subprocess.Popen(args=cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           bufsize=4096)
    stdout, stderr = ret.communicate()
    code = ret.poll()

    return code, stdout, stderr


def update_last_exec_time(name, datetime):
    """
    :param name: 配置文件名
    :param datetime: 策略执行时间
    :return: bool
    """
    try:
        update_policy(name, ['last_exec_time'], [datetime])
    except Exception as error:
        logger.error("FileLifeCycle : update_last_exec_time : %s" % error)


def sync_file(nid, src_dir, retain_days, dst_dir, file_time_type, bw_limit):
    """
    同步源文件到远端目录，成功后删除源文件
    :param nid: 策略id
    :param src_dir:源目录（约定目录名最后不带'/'）
    :param retain_days: 策略设置的保留时间
    :param dst_dir:远端目录（约定目录名最后不带'/'）
    :param file_time_type: 文件时间类型，0-atime, 1-mtime
    :param bw_limit:传输过程的带宽限制
    :return:
    """

    try:
        if dst_dir == "":
            dst_dir = os.path.join(FILE_LIFE_MOUNT_DIR, nid)
            update_policy(nid, ['sync_target_path'], [dst_dir])
        if os.path.isdir(dst_dir) and os.path.isdir(src_dir):
            files_to_sync = get_sync_file_name(src_dir, retain_days, file_time_type)
            if bw_limit == "":
                sync_cmd = "rsync -a --files-from=" + files_to_sync + " --remove-source-files " + src_dir + " " \
                           + dst_dir
            else:
                bw_limit = bw_limit + "m"
                sync_cmd = "rsync -a --files-from=" + files_to_sync + " --bwlimit="+ bw_limit \
                           + " --remove-source-files " + src_dir + " " + dst_dir
            sub = subprocess.Popen(args=sync_cmd,shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           bufsize=4096)
            sub.wait()
            err = sub.stderr.read()
            err_str = err.decode()
            if err_str != '':
                logger.error("nid=%s, rsync process error: %s" % nid % err_str)
        else:
            logger.warning("FileLifeCycle : sync_file : no such directory, "
                           "please check src_dir or dsr_dir")
    except Exception as error:
        logger.error("FileLifeCycle : sync_file : %s" % error)


def get_sync_file_name(src_dir, retain_days, file_time_type):
    """
    得到需要同步的文件列表
    :param src_dir: 源目录
    :param retain_days: 保留天数
    :param file_time_type: 时间类型，0-atime, 1-mtime
    :return: 以文件的形式存储需要同步的文件名（去除src_dir的相对路径，排除目录），文件名是绝对路径
    """

    try:
        handle_timestamp = int(time.time()) - int(retain_days) * 24 * 60 * 60
        stat_format = "%Y:%n"
        if int(file_time_type) == 0:
            stat_format = "%X:%n"
        cmd = "locate '%s/' -0 | xargs -0 stat -c '%s' | awk  -F':' '{if($1 <= %s){print $2}}'" \
              % (src_dir, stat_format, handle_timestamp)
        _, stdout, stderr = exec_cmd(cmd, -1)
        file_to_sync = src_dir + "_to_sync"
        length = len(src_dir)
        stdout = stdout.decode()
        file_list = stdout.split("\n")
        with open(file_to_sync, 'w') as f:
            for file in file_list:
                if os.path.isdir(file):
                    continue
                file_relative_path = file[length+1:]
                f.write(file_relative_path+"\n")
        return file_to_sync
    except Exception as error:
        logger.error("FileLifeCycle : get_sync_file_name : %s" % error)
        return ""
