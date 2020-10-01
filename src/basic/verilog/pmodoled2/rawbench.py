#!/usr/bin/env python3
# Copyright (c) 2015 Wladimir J. van der Laan
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
'''Benchmark rendering'''
from __future__ import division,print_function
import serial,sys,time
from imagefont import ImageFont
from util import bin8,load_bw_image,tile_image
from oleddisplay import OledDisplay,DC
import time

font = ImageFont("fonts/oddball.png")
disp = OledDisplay()

time_start = time.time()
frames = 0
fps_str = ''
while True:
    data = [0]*(128*32//8)
    ptr = 0
    for ch in str(frames):
        data[ptr:ptr+8] = font.glyphs_bw[ord(ch)]
        ptr += 8
    ptr = 16*8
    for ch in fps_str:
        data[ptr:ptr+8] = font.glyphs_bw[ord(ch)]
        ptr += 8

    disp.update(on=DC) # send display data
    disp.spi(data)
    disp.update(off=DC) # back to command mode
    frames += 1
    if (frames%1000)==0:
        curtime = time.time()
        fps_str = '%.1f FPS' % (frames/(curtime-time_start))
        print(fps_str)

