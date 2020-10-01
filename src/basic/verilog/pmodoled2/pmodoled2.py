#!/usr/bin/env python3
# Copyright (c) 2015 Wladimir J. van der Laan
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
'''Implementation of pmodoled2a in terms of OledDisplay'''
from __future__ import division,print_function
import serial,sys,time
from imagefont import ImageFont
from util import bin8,load_bw_image,tile_image
from oleddisplay import OledDisplay,DC

font = ImageFont("fonts/oddball.png")
disp = OledDisplay()

screen = 0
while True:
    #disp.spi([0xB0,0x00,0x10]) # reset write location (alt: set end address appropriately)
    disp.update(on=DC) # send display data
    # Build image
    #screen = 3
    if screen == 0:
        data = [0]*(128*32//8)
        ptr = 0
        for ch in u"\u0157 \u0158 \u0157 Ph'nglui Mglw'nafh Cthulhu R'lyeh wgah'nagl fhtagn \u0157 \u0158 \u0157":
            for col in font.glyphs_bw[ord(ch)]:
                data[ptr] = col
                ptr += 1
    elif screen == 1:
        data = load_bw_image('images/cthulhu.png', ofsy=8)
    elif screen == 2:
        scratch = [[0] * 128 for y in range(32)]
        for l in range(16):
            for y in range(32):
                scratch[y][l*8+4] = 1
        for l in range(4):
            for x in range(128):
                scratch[l*8+4][x] = 1
        data = tile_image(scratch)
    elif screen == 3:
        import random
        shuffle = [x for x in range(64)]
        '''
        bs = [5,1,2,3,4,0]
        for x in range(64):
            bits = [((x>>b)&1) for b in range(6)]
            shuffle[x] = sum(bits[bs[b]]<<b for b in range(6))
        '''
        for x in range(64):
            if (x % 3)==0:
                a = shuffle[x]
                shuffle[x] = 63-x
                shuffle[63-x] = a

        data = [0]*(128*32//8)
        ptr = 0
        for x in range(64):
            x_ = shuffle[x]
            for l in range(8):
                vv = 0
                for i in range(8):
                    bit = random.randint(0, 64) < x_
                    vv |= bit << i
                data[ptr] = vv
                ptr += 1

    # Send image
    disp.spi(data)

    disp.update(off=DC) # back to command mode

    time.sleep(5)
    screen = (screen + 1)% 4

