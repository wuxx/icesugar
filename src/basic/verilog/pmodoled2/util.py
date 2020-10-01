# Copyright (c) 2015 Wladimir J. van der Laan
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
from __future__ import division,print_function
from PIL import Image

def bin8(value):
    svalue = bin(value)[2:]
    svalue = '0'*(8-len(svalue)) + svalue
    return svalue

def load_bw_image(filename, ofsx=0, ofsy=0):
    data = [0]*(128*32//8)
    i = Image.open(filename)
    for y in range(32):
        for x in range(128):
            page = y // 8
            bit = y % 8
            ofs = x
            if i.getpixel((ofsx+x,ofsy+y)):
                data[page*128+ofs] |= 1<<bit
    return data

def tile_image(ingrid):
    '''
    Convert image to tiled SSD1306 representation
    '''
    data = [0]*(128*32//8)
    for y in range(32):
        for x in range(128):
            page = y // 8
            bit = y % 8
            ofs = x
            if ingrid[y][x]:
                data[page*128+ofs] |= 1<<bit
    return data

def detect_serial():
    '''Detect serial port for iCESugar.
    Based on 'findserial' in swapforth.
    '''
    import glob, subprocess
    return glob.glob('/dev/tty.usbmodem*')
    # options = []
    # for dev in glob.glob('/dev/ttyUSB*'):
    #     info = subprocess.check_output(['/sbin/udevadm', 'info', '-a', '-n', dev])
    #     info = info.split(b'\n')
    #     vendor_matches = False
    #     product_matches = False
    #     for line in info:
    #         if b'ATTRS{idVendor}=="0403"' in line:
    #             vendor_matches = True
    #         if b'ATTRS{idProduct}=="6010"' in line:
    #             product_matches = True
    #     if vendor_matches and product_matches:
    #         options.append(dev)
    # return options

