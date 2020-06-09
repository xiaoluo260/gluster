#!/usr/bin/python
# -*- coding: utf-8 -*-

#
# extract-glvolprof.py
# written by z 2019
#


import sys
import os
import re
from collections import OrderedDict
from decimal import Decimal


def usage(msg):
    print('ERROR: %s' % msg)
    sys.exit(1)


class ProfileInterval:

    def __init__(self):
        self.space_free = 0
        self.space_disk = 0
        self.brick_name = None


# convert gvp-client.sh client profile output
# into a time series of per-fop results.
def parse_vol_info(input_pathname):
    global disperse_count
    global disperse_data
    global bricks_dict
    global replica_count
    global replica_data

    try:
        with open(input_pathname, 'r') as file_handle:
            lines = [l.strip() for l in file_handle.readlines()]
    except IOError:
        usage('could not read ' + input_pathname)
    bricks_dict = OrderedDict()
    for ln in lines:
        tokens = ln.strip().split("=")
        if ln.startswith('count'):
            total_brick = int(tokens[1])
        elif ln.__contains__('disperse_count'):
            disperse_count = int(tokens[1])
        elif ln.__contains__('redundancy_count'):
            disperse_data = disperse_count - int(tokens[1])
        elif ln.__contains__('replica_count'):
            replica_count = int(tokens[1])
            replica_data = replica_count
        elif ln.__contains__('arbiter_count'):
            replica_data = replica_count - int(tokens[1])
        elif ln.startswith('brick'):
            brick_name = tokens[1].replace('-', '/')
            bricks_in_interval = ProfileInterval()
            bricks_dict[brick_name] = bricks_in_interval
    assert total_brick == len(bricks_dict)



def parse_input_disperse(input_pathname):
    try:
        with open(input_pathname, 'r') as file_handle:
            lines = [l.strip() for l in file_handle.readlines()]
    except IOError:
        usage('could not read ' + input_pathname)

    found_brick_output = False

    for ln in lines:
        tokens = ln.strip().split()

        if ln.startswith('Brick'):

            brick_name = tokens[-1]
            found_brick_output = True
            bricks_in_interval = bricks_dict.get(brick_name)

        elif ln.startswith('Disk'):

            if found_brick_output:
                # space_free = float(re.findall(r'\d+\.?\d*', tokens[-1])[0])
                space = re.findall(r'\d+\.?\d*', tokens[-1])[0]
                unit = tokens[-1].strip(space)
                space_free = unit_converter(float(space), unit, "TB", 2)
                bricks_in_interval.space_free = space_free

        elif ln.startswith('Total'):

            if found_brick_output:
                # space_disk = float(re.findall(r'\d+\.?\d*', tokens[-1])[0])
                # bricks_in_interval.space_disk = space_disk
                space = re.findall(r'\d+\.?\d*', tokens[-1])[0]
                unit = tokens[-1].strip(space)
                space_total = unit_converter(float(space), unit, "TB", 2)
                bricks_in_interval.space_disk = space_total
                found_brick_output = False


def parse_input_replica(input_pathname):
    try:
        with open(input_pathname, 'r') as file_handle:
            lines = [l.strip() for l in file_handle.readlines()]
    except IOError:
        usage('could not read ' + input_pathname)

    found_brick_output = False

    for ln in lines:
        tokens = ln.strip().split()

        if ln.startswith('Brick'):

            brick_name = tokens[-1]
            found_brick_output = True
            bricks_in_interval = bricks_dict.get(brick_name)

        elif ln.startswith('Disk'):

            if found_brick_output:
                # space_free = float(re.findall(r'\d+\.?\d*', tokens[-1])[0])
                space = re.findall(r'\d+\.?\d*', tokens[-1])[0]
                unit = tokens[-1].strip(space)
                space_free = unit_converter(float(space), unit, "TB", 2)
                bricks_in_interval.space_free = space_free

        elif ln.startswith('Total'):

            if found_brick_output:
                # space_disk = float(re.findall(r'\d+\.?\d*', tokens[-1])[0])
                # bricks_in_interval.space_disk = space_disk
                space = re.findall(r'\d+\.?\d*', tokens[-1])[0]
                unit = tokens[-1].strip(space)
                space_total = unit_converter(float(space), unit, "TB", 2)
                bricks_in_interval.space_disk = space_total
                found_brick_output = False

# space_disk space_free
def write_to_outfile(total,free,outfile):
    try:
        with open(outfile, 'w') as file_handle:
            file_handle.write(str(total) +',' +str(free))
    except IOError:
        usage('could not wirte ' + outfile)



def generate_output_disperse(outfile):
    tmp1 = 0
    tmp2 = 0
    index = 0
    total_space = 0
    free_space = 0
    for brick_key, brick_class in bricks_dict.items():
        if index < disperse_count:
            if brick_class.space_disk and brick_class.space_free:
                if tmp1 == 0:
                    tmp1 = brick_class.space_disk
                    tmp2 = brick_class.space_free
                elif tmp1 > brick_class.space_disk:
                    tmp1 = brick_class.space_disk
                    tmp2 = brick_class.space_free

            index = index + 1
        else:
            total_space = total_space + tmp1 * disperse_data
            free_space = free_space + tmp2 * disperse_data
            if brick_class.space_disk and brick_class.space_free:
                tmp1 = brick_class.space_disk
                tmp2 = brick_class.space_free
            else:
                tmp1 = 0
                tmp2 = 0
            index = 0
    total_space = total_space + tmp1 * disperse_data
    free_space = free_space + tmp2 * disperse_data
    #print(tmp) 由输出终端改为输出文件
    write_to_outfile(total_space,free_space,outfile)


def generate_output_replica(outfile):
    tmp1 = 0
    tmp2 = 0
    index = 0
    total_space = 0
    free_space = 0
    for brick_key, brick_class in bricks_dict.items():
        if index < replica_data:
            if brick_class.space_disk and brick_class.space_free:
                if tmp1 == 0:
                    tmp1 = brick_class.space_disk
                    tmp2 = brick_class.space_free
                elif tmp1 > brick_class.space_disk:
                    tmp1 = brick_class.space_disk
                    tmp2 = brick_class.space_free

            index = index + 1
        else:
            total_space = total_space + tmp1
            free_space = free_space + tmp2
            #仲裁盘容量不考虑
            if brick_class.space_disk and brick_class.space_free:
                tmp1 = 0
                tmp2 = 0
            index = 0

    #print(tmp) 由输出终端改为输出文件
    write_to_outfile(total_space,free_space,outfile)

def generate_output_replica_noar(outfile):
    tmp1 = 0
    tmp2 = 0
    index = 0
    total_space = 0
    free_space = 0
    for brick_key, brick_class in bricks_dict.items():
        if index < replica_data:
            if brick_class.space_disk and brick_class.space_free:
                if tmp1 == 0:
                    tmp1 = brick_class.space_disk
                    tmp2 = brick_class.space_free
                elif tmp1 > brick_class.space_disk:
                    tmp1 = brick_class.space_disk
                    tmp2 = brick_class.space_free

            index = index + 1
        else:
            total_space = total_space + tmp1
            free_space = free_space + tmp2
            #仲裁盘容量不考虑
            if brick_class.space_disk and brick_class.space_free:
                tmp1 = brick_class.space_disk
                tmp2 = brick_class.space_free
            index = 1
    total_space = total_space + tmp1
    free_space = free_space + tmp2
    #print(tmp) 由输出终端改为输出文件
    write_to_outfile(total_space,free_space,outfile)

def unit_converter(float_value, unit_old, unit_new, num=2):
    """
    单位数值转换器
    将指定单位数值转换为另一指定单位的数值
    :param float float_value: 单位数值，例：4294967.2960、200039893.4016
    :param string unit_old: 原数值指定单位，仅支持'B'、'KB'、'MB'、'GB'、'TB'
    :param string unit_new: 转换数值指定单位，仅支持'B'、'KB'、'MB'、'GB'、'TB'
    :param int num: 保留的小数位数，0 为不保留，默认保留两位小数
    :return: float result: 指定单位的数值，四舍五入，例：40.00、1.82
    """
    # 单位对应1024的N次方
    unit_leave = {
        'B': 0,
        'KB': 1,
        'MB': 2,
        'GB': 3,
        'TB': 4
    }

    # 获取原数值和转换数值的次方数
    old_unit_leave = unit_leave[unit_old]
    new_unit_leave = unit_leave[unit_new]

    # 判断转换关系
    if old_unit_leave > new_unit_leave:
        # 由大转小
        mul_times = old_unit_leave - new_unit_leave
        float_unit = float_value * pow(1024, mul_times)

    elif old_unit_leave < new_unit_leave:
        # 由小转大
        dev_times = new_unit_leave - old_unit_leave
        float_unit = float_value / pow(1024, dev_times)

    else:
        # 单位不变，仅执行四舍五入操作
        float_unit = float_value

    # 保留num位小数，四舍五入

    num_cut_list = ['0'] * num if num else []
    num_cut = '0.' + ''.join(num_cut_list) if num_cut_list else '0'
    str_unit = str(Decimal(str(float_unit)).quantize(Decimal(num_cut)))

    return float(str_unit)


def main():
    if len(sys.argv) < 4:
        usage('missing gluster  tmp-log volume-info parameter')
    fn = sys.argv[1]
    fn_vol = sys.argv[2]
    outputfile = sys.argv[3]
    parse_vol_info(fn_vol)
    if disperse_count > 1:
        parse_input_disperse(fn)
        generate_output_disperse(outputfile)
    elif replica_count > replica_data:
        parse_input_replica(fn)
        generate_output_replica(outputfile)
    elif replica_count == replica_data:
        parse_input_replica(fn)
        generate_output_replica_noar(outputfile)


main()
