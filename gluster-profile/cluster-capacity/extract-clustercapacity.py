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
    try:
        with open(input_pathname,'r') as file_handle:
            lines = [l.strip() for l in file_handle.readlines() ]
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
        elif ln.startswith('brick'):
            brick_name = tokens[1].replace('-','/')
            bricks_in_interval = ProfileInterval()
            bricks_dict[brick_name] = bricks_in_interval	
    assert total_brick == len(bricks_dict)
	

def parse_input(input_pathname):
    try:
        with open(input_pathname, 'r') as file_handle:
            lines = [ l.strip() for l in file_handle.readlines() ]
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
                space_free = float(re.findall(r'\d+\.?\d*',tokens[-1])[0])
                bricks_in_interval.space_free = space_free
			
        elif ln.startswith('Total'):

            if found_brick_output:
                space_disk = float(re.findall(r'\d+\.?\d*',tokens[-1])[0])
                bricks_in_interval.space_disk = space_disk
                found_brick_output = False



		



# space_disk space_free

def generate_output():

	tmp1 = 0
	tmp2 = 0
	index = 0
	total_space = 0
	free_space = 0
	for brick_key,brick_class in bricks_dict.items():
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
			total_space = total_space + tmp1*disperse_data
			free_space = free_space + tmp2*disperse_data 
			if brick_class.space_disk and brick_class.space_free:
				tmp1 = brick_class.space_disk
				tmp2 = brick_class.space_free					
			else:
				tmp1 = 0
				tmp2 = 0
			index = 0
	total_space = total_space + tmp1*disperse_data
	free_space = free_space + tmp2*disperse_data
	print(total_space, free_space)


def main():
    if len(sys.argv) < 3:
        usage('missing gluster  tmp-log volume-info parameter')
    fn = sys.argv[1]
    fn_vol = sys.argv[2]
    parse_vol_info(fn_vol)
    parse_input(fn)
    generate_output()

main()




