# -*- coding: utf-8 -*-
from config.logconfig import notifier_logger as logger
import time
import os
import datetime
import calendar


def is_dir_expiration(handle_time, last_exec_time, handle_type, handle_value):
    """
    判断是否满足执行条件
    :param handle_time: 第一次执行检查时要检查handle_time, 格式为%H:%M
    :param last_exec_time: 上次的执行时间，多次执行后根据上次执行时间+ 时间间隔与当前时间比较
    :param handle_type: 执行策略的时间类型（天、周、月）
    :param handle_value: 执行策略的数值
    :return: bool
    """
    ret = False
    try:
        cur_timestamp = int(time.time())
        # 间隔n天执行
        if handle_type == 0: #天
            today = time.strftime("%Y-%m-%d", time.localtime(time.time()))#2020-06-19
            handle_time_str = "%s %s:00" % (today, str(handle_time))#2020-06-19 09:12:00
            secs_per_day = int(24 * 60 * 60)# 1天
            interval_seconds = int(handle_value) * secs_per_day# 策略秒
            if last_exec_time == '' and handle_time != '':#第一次检查
                handle_time_secs = int(time.mktime(time.strptime(str(handle_time_str), "%Y-%m-%d %H:%M:%S"))) #返回秒
                if cur_timestamp >= handle_time_secs:
                    ret = True
            elif last_exec_time != '':
                last_exec_time_secs = int(time.mktime(time.strptime(last_exec_time, "%Y-%m-%d %H:%M:%S")))#上一次检查的时间 
                if last_exec_time_secs + interval_seconds <= cur_timestamp:#达到策略值
                    ret = True

        # 每周定时执行
        elif handle_type == 1:
            weekday = datetime.datetime.now().isoweekday()#周5
            if weekday == int(handle_value):
                handle_time_str = str(handle_time)#第一次检查的时间
                now = time.strftime("%H-%M", time.localtime(time.time()))#当前09：20
                ret = is_timeout(now, handle_time_str)#判断是否超时

        # 每月定时执行
        elif handle_type == 2:
            now_day = datetime.datetime.now().day
            now_month = datetime.datetime.now().month
            max_day = calendar.mdays[now_month] #本月共多少天
            handle_day = int(handle_value) #策略值
            if handle_day > max_day:
                handle_day = max_day
            if now_day == handle_day: #非本日 不执行
                handle_time_str = str(handle_time)
                now = time.strftime("%H-%M", time.localtime(time.time()))
                ret = is_timeout(now, handle_time_str) # 当前时间超过默认检查时间 ，则true
    except Exception as error:
        logger.error("FileLifeCycle: is_dir_expiration: %s" % error)
    return ret


def is_timeout(now, handle_time_str):
    """
    判断是否超时
    :param now:%H-%M
    :param handle_time_str:%H:%M
    :return: bool
    """
    ret = False
    try:
        handle_hour = handle_time_str.split(":")[0]
        handle_minute = handle_time_str.split(":")[1]
        now_hour = now.split("-")[0]
        now_minute = now.split("-")[1]
        if handle_hour[0] == "0":
            handle_hour = handle_hour[1]
        if handle_minute[0] == "0":
            handle_minute = handle_minute[1]
        if now_hour[0] == "0":
            now_hour = now_hour[1]
        if now_minute[0] == "0":
            now_minute = now_minute[1]
        now_hour_int = int(now_hour)
        now_minute_int = int(now_minute)
        handle_hour_int = int(handle_hour)
        handle_minute_int = int(handle_minute)
        if now_hour_int > handle_hour_int:
            ret = True
        elif now_hour_int == handle_hour_int and now_minute_int >= handle_minute_int:
            ret = True
    except Exception as error:
        logger.error("FileLifeCycle: is_timeout: %s" % error)
    return ret

# 使用绝对路径
def list_all_files(root_dir):
    """
    function：列举目录下的所有文件，返回一个list
    @param root_dir: 根目录
    @return: 文件名list
    """
    files = []
    depth = os.listdir(root_dir)
    for i in range(0, len(depth)):
        path = os.path.join(root_dir, depth[i])
        if os.path.isdir(path):
            files.extend(list_all_files(path))
        if os.path.isfile(path):
            files.append(path)
    return files


