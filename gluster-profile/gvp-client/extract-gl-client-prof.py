#!/usr/bin/python
# -*- coding: utf-8 -*-

#
# extract-gl-client-prof.py
# written by z 2019



import sys
import os


# fields in gluster volume profile output

#stat_names = ['MBps-read', 'MBps-written', 'IOPS-read', 'IOPS-written', 'avg-lat-read/us', 'avg-lat-write/us']
stat_names = "MBps-read MBps-written IOPS-read IOPS-written"

def usage(msg):
    print('ERROR: %s' % msg)
    sys.exit(1)

class ProfileInterval:

    def __init__(self):
        self.bytes_read = 0.0
        self.bytes_written = 0.0
        self.duration = 1
        self.write_iocall = 0
        self.write_latency = 0
        self.read_iocall = 0
        self.read_latency = 0
		


def find_interval_line_number(all_lines):
    n = -1
    for ln in reversed(all_lines):
        if ln.__contains__('Interval') and ln.__contains__('stats'):
            return  int(len(all_lines)+n)
        n = n-1
    return -1
	
	
# convert gvp-client.sh client profile output
# into a time series of per-fop results.

def parse_input(input_pathname):
    global intervals

    try:
        with open(input_pathname, 'r') as file_handle:
            lines = [ l.strip() for l in file_handle.readlines() ]
    except IOError:
        usage('could not read ' + input_pathname)
    n = find_interval_line_number(lines)
    duration = 1
    intervals = ProfileInterval()
    found_interval_output = False

    for ln in lines[n:]:
        tokens = ln.split()

        if ln.__contains__('Interval') and ln.__contains__('stats'):

            found_interval_output = True

        elif ln.__contains__('Cumulative Stats'):

            found_interval_output = False

        elif ln.__contains__('Duration :'):

            if found_interval_output:
                duration = int(tokens[2])
                if duration:				
                    intervals.duration = duration
        elif ln.__contains__('BytesRead'):

            if found_interval_output and duration:
                intervals.bytes_read = round(((float(tokens[2])/duration)/1024)/1024,2)

        elif ln.__contains__('BytesWritten'):

            if found_interval_output and duration:
                intervals.bytes_written = round(((float(tokens[2])/duration)/1024)/1024,2)


        elif ln.__contains__('WRITE'):

            if found_interval_output:
                intervals.write_iocall = int(tokens[1])/duration
                intervals.write_latency = float(tokens[2])

        elif ln.__contains__('READ'):

            if found_interval_output:
                intervals.read_iocall = int(tokens[1])/duration
                intervals.read_latency = float(tokens[2])




# generate everything needed to view the graphs

def generate_output(outfile):

    #print(tmp) 由输出终端改为输出文件
    try:
        with open(outfile, 'w') as file_handle:
            file_handle.write(str(intervals.bytes_read)+',' +str(intervals.bytes_written)+',' +str(intervals.read_iocall)+',' +str(intervals.write_iocall))
    except IOError:
        usage('could not wirte ' + outfile)

        	


# the main program is kept in a subroutine so that it can run on Windows.

def main():
    if len(sys.argv) < 3:
        usage('missing gluster volume profile filename parameter'
              )
    fn = sys.argv[1]
    parse_input(fn)
    outputfile = sys.argv[2]
    generate_output(outputfile)

main()
