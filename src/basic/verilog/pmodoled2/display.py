# Copyright (c) 2015 Wladimir J. van der Laan
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
'''
Base classes for Display, console-based emulation
'''
from __future__ import division,print_function
import sys

class BaseDisplay:
    '''
    Base class for external grid displays.
    '''
    width = None
    height = None
    def __init__(self):
        pass

    def set_image(self, data):
        '''
        Send image to display.
        Input: width * height 2D array of 0,1 values.
        '''
        pass

class ConsoleDisplay(BaseDisplay):
    '''
    Simple console based 'display'.
    '''
    def __init__(self):
        sys.stdout.write('\x1b[H\x1b[J')
        self.width = 128
        self.height = 32

    def set_image(self, data):
        sys.stdout.write('\x1b[H')
        for y in range(0,self.height):
            s = []
            for x in range(0,self.width):
                if data[y][x]:
                    s.append('x')
                else:
                    s.append(' ')
            sys.stdout.write((''.join(s)) + '\n')


