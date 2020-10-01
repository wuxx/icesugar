#!/usr/bin/env python3
# Copyright (c) 2015 Wladimir J. van der Laan
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
'''
Smooth Mandelbrot rendering using numpy.
'''
from __future__ import division,print_function
from display import ConsoleDisplay
from oleddisplay import OledDisplay
import numpy as np

def mandelbrot(c, iterations=20):
    '''
    Compute mandelbrot set at coordinate c,
    return True if inside or False if outside.
    '''
    z = 0+0j
    i = 0
    while abs(z) < 2 and i < iterations:
        z = (z * z) + c
        i += 1
    return i >= iterations

def find_edge(c1, c2, func):
    '''
    Find edge of mandelbrot set using bisection method.
    Input: c1, a point on the set, c2 a point not on the set.
    Returns: (c1',c2')
    '''
    midpoint = (c1 + c2) / 2
    if func(midpoint):
        return (midpoint, c2) # midpoint on set, c2 not on set
    else:
        return (c1, midpoint) # c1 on set, midpoint not on set

def random_point():
    '''Find random point on Mandelbrot set'''
    import random
    ofs1 = complex(0,0) # on mandelbrot set
    ofs2 = (1j ** (random.random()*4)) * 2 # not on mandelbrot set
    #ofs1 = complex(0.02996, 0.80386) # on mandelbrot set
    #ofs2 = complex(0.02997, 0.80386) # not on mandelbrot set
    for i in range(64):
        (ofs1, ofs2) = find_edge(ofs1, ofs2, mandelbrot)
    return ofs1
    # what are interesting points?
    # https://en.wikipedia.org/wiki/Misiurewicz_point

#disp = ConsoleDisplay()
disp = OledDisplay()

WW = disp.width
HH = disp.height
fovy = HH/WW

xx,yy = np.meshgrid(np.linspace(-1.0, 1.0, WW), np.linspace(-1.0, 1.0, HH))
ii = xx + 1j*yy*fovy
iterations_outer = 2
iterations_inner = 20

while True:
    ofs = random_point()
    #ofs = -0.77568377 + 0.13646737j   # M23,2
    #ofs = -1.54368901269109  # M3,1
    #ofs = -0.1010 + 0.9562j  # M4,1
    #ofs = 0.3994999999988 + 0.195303j

    frame = 0
    while True:
        zoom = 2.0**((frame-600)/200.0)

        # Compute mandelbrot in parallel with numpy
        c = ii / zoom + ofs
        z = np.zeros((HH,WW),dtype=complex)
        for i in range(iterations_inner):
            if i == iterations_outer: # for showing outer boundary
                zb = z
            z = (z * z) + c
        data = np.abs(z) < 2
        boundary = np.abs(zb) < 2

        # Boundary
        disp.set_image(np.invert(data) & boundary)

        if np.all(data) or not np.any(data):
            # stop if there is nothing to see anymore
            break
        frame += 1

