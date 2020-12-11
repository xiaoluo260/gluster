# -*- coding: utf-8 -*-
import time
from concurrent.futures import ThreadPoolExecutor
from config.logconfig import notifier_logger as logger
from config.config import THREAD_NUM
from file_io import get_policy
from config.config import CONFIG_DIR
from Watcher.watcher import update_last_exec_time
from Watcher.watcher import sync_file
from Notifier.notifier import is_dir_expiration
from Notifier.notifier import list_all_files
from config.config import CHECK_INTERVAL

def run():
        with ThreadPoolExecutor(max_workers=THREAD_NUM) as pool: #线程池
            while True:
                file_list = list_all_files(CONFIG_DIR) #/etc/file_life_cycle/文件列表
                for filename in file_list:
                    try:
                        policy = get_policy(filename)# 将文件内容 json格式化输出 文件记录了某个目录的名称，上次同步时间，同步策略
                        if is_dir_expiration(policy['handle_time'], policy['last_exec_time'], policy['cycle_type'],
                                             policy['cycle_value']) and policy['is_use'] == '1':
                                             #handle_time 文件时间， last上次检查时间，type策略时间类型，value策略值，use正在读写；判断条件满足与否，true表示满足
                            update_last_exec_time(policy['nid'], time.strftime("%Y-%m-%d %H:%M:%S"))#文件名 格式 更新last_exec_time
                            #开始同步文件 10线程  文件名，源目录，保持时间，目的目录，文件类型，带宽
                            pool.submit(sync_file, policy['nid'], policy['sync_source_path'], policy['retain_days'],
                                        policy['sync_target_path'], policy['file_time_type'], policy['bw_limit'])
                    except Exception as error:
                        logger.error("FileLifeCycle: run : %s" % error)
                time.sleep(CHECK_INTERVAL)
