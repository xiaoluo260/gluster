#!/usr/bin/python
# -*- coding: utf-8 -*-

#
# extract-glvolprof.py
# written by z 2019
#


import sys
import os


# fields in gluster volume profile output



def usage(msg):
    print('ERROR: %s' % msg)
    sys.exit(1)

class ProfileInterval:

    def __init__(self):
        self.num_need_heal = 0
        self.brick_name = None
		


# convert gvp-client.sh client profile output
# into a time series of per-fop results.

def parse_input(input_pathname):
    global intervals

    try:
        with open(input_pathname, 'r') as file_handle:
            lines = [ l.strip() for l in file_handle.readlines() ]
    except IOError:
        usage('could not read ' + input_pathname)

    found_brick_output = False
    intervals = []
    num_need_heal = 0

    for ln in lines:
        tokens = ln.strip().split()

        if ln.startswith('Brick'):
		
            brick_name = tokens[1]
            found_brick_output = True
            bricks_in_interval = ProfileInterval()
            bricks_in_interval.brick_name = brick_name
            intervals.append(bricks_in_interval)
 
        elif ln.__contains__('Status') and ln.__contains__('not'):

            found_brick_output = False
            bricks_in_interval.num_need_heal = -1
			
        elif ln.startswith('Total'):

            if found_brick_output:
                num_need_heal = int(tokens[-1])
                bricks_in_interval.num_need_heal = num_need_heal


		



# generate everything needed to view the graphs

def generate_output():

    tmp = 0
    for brick_intervals in intervals:
        if brick_intervals.num_need_heal > tmp:
            tmp = brick_intervals.num_need_heal	
    print(tmp)


def main():
    if len(sys.argv) < 2:
        usage('missing gluster volume profile output log filename parameter')
    fn = sys.argv[1]
    parse_input(fn)
    generate_output()

main()




