#!/usr/bin/env python3
# Copyright (c) 2015 Wladimir J. van der Laan
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
'''Typing directly to display'''
from __future__ import division,print_function
import sys,time
from imagefont import ImageFont
from util import bin8,load_bw_image,tile_image
from oleddisplay import OledDisplay,DC
import time
import curses

font = ImageFont("fonts/oddball.png")
disp = OledDisplay()

stdscr = curses.initscr()
curses.noecho()
curses.cbreak()
stdscr.keypad(1)

try:
    disp.update(on=DC) # send display data
    ofs = 0
    while True:
        ch = stdscr.getch()
        if ch == 27:
            break
        elif ch == 10:
            n = 16 - (ofs % 16)
            disp.spi(font.glyphs_bw[0x20] * n)
            ofs += n
        elif ch < len(font.glyphs_bw):
            disp.spi(font.glyphs_bw[ch])
            ofs += 1
    disp.update(off=DC) # back to command mode
finally:
    curses.nocbreak()
    stdscr.keypad(0)
    curses.echo()
    curses.endwin()

