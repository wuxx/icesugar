# Copyright (c) 2015 Wladimir J. van der Laan
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
'''
Serial OLED display driving logic.
'''
from __future__ import division,print_function
import serial,sys,time
from imagefont import ImageFont
from util import bin8,load_bw_image,tile_image,detect_serial
from display import BaseDisplay

# Flag bits
CS   = (1<<4) # chip select if low
DC   = (1<<3)  # command if low, data if high
RES  = (1<<2)  # reset if low
VBATC= (1<<1)  # power control display; active-low
VDDC = (1<<0)  # power control logic; active-low

class OledDisplay(BaseDisplay):
    width = 128
    height = 32
    def __init__(self, port=None):
        if port is None:
            ports = detect_serial()
            if len(ports) == 0:
                raise IOError('No iCEStick devices detected')
            if len(ports) > 1:
                raise IOError('Multiple possible iCEStick devices detected. Need to specify which one to use')
            port = ports[0]
        self.conn = serial.serial_for_url(port, 1000000,
             parity=serial.PARITY_NONE, rtscts=False, xonxoff=False, timeout=1)

        self.value = 0

        # Send 33 NOPs to reset and sync serial
        self.conn.write(bytearray([0x00] * 33))

        # Select chip, go to command mode, turn off reset and power
        self.update(off=CS|DC,on=RES|VBATC|VDDC)
        # 1. Apply power to VDD.
        self.update(off=VDDC)
        # 2. Send Display Off command (0xAE)
        self.spi(0xAE)
        # Reset
        self.update(off=RES)
        time.sleep(0.000003) # at least 3us
        self.update(on=RES)
        # 3. Initialize display to desired operating mode.
        self.spi([0x8D,0x14]) # charge pump
        self.spi([0xD9,0xF1]) # precharge
        # 4. Clear screen.
        self.spi([0x20,0x00]) # horizontal addressing mode
        self.spi([0x22,0x00,0x03]) # page start and end address (create wraparound at line 32)
        self.set_image([[0]*self.width for x in range(self.height)])
        # 5. Apply power to VBAT.
        self.update(off=VBATC)
        # Misc configuration
        self.spi([0x81,0x0F]) # contrast
        self.spi([0xA1,0xC8]) # invert display
        self.spi([0xDA,0x20]) # comconfig

        # 6. Delay 100ms.
        time.sleep(0.1)
        # 7. Send Display On command (0xAF).
        self.spi(0xAF)

        # Debugging:
        #spi(0xA5) # full display
        #spi(0xA4) # display according to memory
        #spi([0x20,0x01]) # vertical addressing mode

    def update(self, off=0, on=0):
        self.value &= ~off
        self.value |= on
        self.conn.write(bytearray([0b00100000 | self.value]))
        #print('Write %s SCLK=%i SDIN=%i' % (bin8(value), bool(value&SCLK), bool(value&SDIN)))
        #print('OUT %02x' % (0b00100000 | value))

    def spi(self, data_values):
        '''Clock 8-bit value(s) to SPI'''
        import binascii
        if not isinstance(data_values, list):
            data_values = [data_values]
        # Value of SDIN is sampled at SCLK's rising edge
        # so put in new bit at falling edge
        # Data is clocked from bit 7 (MSB) to bit 0 (LSB)
        ptr = 0
        while ptr < len(data_values):
            n = min(len(data_values)-ptr, 16)
            self.conn.write(bytearray([0b00010000 | (n-1)] + data_values[ptr:ptr+n]))
            # print('SPI %02x %s' % (0b00010000 | (n-1), binascii.b2a_hex(bytearray(data_values[ptr:ptr+n]))))
            ptr += n
  
    def set_image(self, data):
        '''Send 128x32 image to display.
        Input must be 128x32 array of booleans or 0/1.
        '''
        self.update(on=DC) # send display data
        self.spi(tile_image(data))
        self.update(off=DC) # back to command mode

