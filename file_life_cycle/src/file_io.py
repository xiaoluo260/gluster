# -*- coding: utf-8 -*-
import os
import fcntl
import json
from config.config import CONFIG_DIR
from config.logconfig import notifier_logger as logger


if not os.path.exists(CONFIG_DIR):
    os.mkdir(CONFIG_DIR)


def add_policy(**policy):
    """
    :param: policy: 策略
    :return: bool
    注意：json.dumps(ensure_ascii=False)在读写的时候必须要统一，否则读写会出错！
    """
    ret = False
    try:
        absolute_path = os.path.join(CONFIG_DIR, policy['nid'] + '.conf')
        if os.path.exists(absolute_path):
            return ret
        with open(absolute_path, 'w') as f:
            j_str = json.dumps(policy, ensure_ascii=False)
            f.write(j_str)
        ret = True
    except Exception as error:
        logger.error("FileLifeCycle: add_policy: %s" % error)
    return ret


def get_policy(absolute_path):
    """
    :param: absolute_path: 文件绝对路径
    :return: json 对象
    """
    policy = {}
    try:
        with open(absolute_path, 'r') as f:
            policy_str = f.read()
            if policy_str:
                policy = json.loads(policy_str)
    except Exception as error:
        logger.error("FileLifeCycle: get_policy: %s" % error)
    return policy


def update_policy(name, param_list, value_list):
    """
    :param: name: 文件名
    :param: param_list 需要修改的项
    :param: value_list 修改值
    :return: bool
    """
    ret = False
    try:
        absolute_path = os.path.join(CONFIG_DIR, name + '.conf')
        with open(absolute_path, 'r+') as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)#如果已加锁 则阻塞
            policy_str = f.read()
            if policy_str:
                policy = json.loads(policy_str)
                for i in range(len(param_list)):#len(['last_exec_time']) =1, 
                    policy[param_list[i]] = value_list[i]
                policy_str = json.dumps(policy, ensure_ascii=False)#写回json格式
                f.seek(0)#覆盖
                f.write(policy_str)
                f.truncate() #从当前位置截断文件
        ret = True
    except Exception as error:
        logger.error("FileLifeCycle: update_policy: %s" % error)
    return ret


def rm_policy(name):
    """
    :param: name: 文件名
    :return: bool
    """
    ret = False
    try:
        absolute_path = os.path.join(CONFIG_DIR, name + '.conf')
        if os.path.exists(absolute_path):
            os.unlink(absolute_path)
            ret = True
    except Exception as error:
        logger.error("FileLifeCycle: rm_policy: %s" % error)
    return ret


def set_handle_time(name, datetime):
    """
    :param: name: 文件名
    :param: datetime: 时间戳
    :return: bool
    """
    return update_policy(name, ['last_exec_time', 'handle_time'], ['', datetime])
