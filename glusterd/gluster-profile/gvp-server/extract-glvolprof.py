#!/usr/bin/python
# -*- coding: utf-8 -*-

#
# extract-glvolprof.py
# written by z 2019
#


import sys
import os


# fields in gluster volume profile output

stat_names = "brick_name MBps-read MBps-written IOPS-read IOPS-written"

def usage(msg):
    print('ERROR: %s' % msg)
    sys.exit(1)

class ProfileInterval:

    def __init__(self):
        self.bytes_read = 0.0
        self.bytes_written = 0.0
        self.duration = 1
        self.iocall_write = 0
        self.avg_lat_write = 0
        self.iocall_read = 0
        self.avg_lat_read = 0
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

    found_interval_output = False
    intervals = []
    duration = 1
    for ln in lines:
        tokens = ln.strip().split()

        if ln.startswith('Brick:'):
		
            brick_name = tokens[1]
            found_interval_output = False
            bricks_in_interval = ProfileInterval()
            bricks_in_interval.brick_name = brick_name
            intervals.append(bricks_in_interval)
 

        elif ln.__contains__('Interval') and ln.__contains__('Stats'):

            found_interval_output = True


        elif ln.__contains__('Cumulative Stats'):

            found_interval_output = False

        elif ln.__contains__('Duration:'):

            # we are at end of output for this brick and interval


            if found_interval_output:   
                duration = int(tokens[1])
                if duration:				
                    bricks_in_interval.duration = duration

        elif ln.__contains__('Data Read:'):
            if found_interval_output and duration:
                bytes_read = round(((float(tokens[2])/duration)/1024)/1024,2)
                bricks_in_interval.bytes_read = bytes_read

        elif ln.__contains__('Data Written'):
            if found_interval_output and duration:
                bytes_written = round(((float(tokens[2])/duration)/1024)/1024,2)
                bricks_in_interval.bytes_written = bytes_written

        elif ln.endswith('WRITE'):
            if found_interval_output:
                iocall_write = int(tokens[-2])
                avg_lat_write = float(tokens[1])
                bricks_in_interval.iocall_write = iocall_write	
                bricks_in_interval.avg_lat_write = avg_lat_write	
        elif ln.endswith('READ'):		
            if found_interval_output:
                iocall_read = int(tokens[-2])
                avg_lat_read = float(tokens[1])
                bricks_in_interval.iocall_read = iocall_read	
                bricks_in_interval.avg_lat_read = avg_lat_read			
		



# generate everything needed to view the graphs

def generate_output(outfile):

    total_MB_read = 0
    total_MB_write = 0
    total_IOPS_read = 0
    total_IOPS_write = 0
    for brick_intervals in intervals:
        assert brick_intervals.duration or 0
        total_MB_read = total_MB_read + brick_intervals.bytes_read
        total_MB_write = total_MB_write + brick_intervals.bytes_written
        total_IOPS_read = total_IOPS_read + brick_intervals.iocall_read/brick_intervals.duration
        total_IOPS_write = total_IOPS_write + brick_intervals.iocall_write/brick_intervals.duration			
    #print(tmp) 由输出终端改为输出文件
    try:
        with open(outfile, 'w') as file_handle:
            file_handle.write(str(total_MB_read)+',' +str(total_MB_write)+',' +str(total_IOPS_read)+',' +str(total_IOPS_write))
    except IOError:
        usage('could not wirte ' + outfile)
        	

def main():
    if len(sys.argv) < 3:
        usage('missing gluster volume profile  filename parameter')
    fn = sys.argv[1]
    outputfile = sys.argv[2]
    parse_input(fn)
    generate_output(outputfile)

main()




