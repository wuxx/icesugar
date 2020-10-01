# Copyright (c) 2015 Wladimir J. van der Laan
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
'''
Simple image font
'''
# TODO: support different image formats than RGBA
from __future__ import division,print_function
from PIL import Image

THRESHOLD=128 # pixel values >= this are considered hi, else lo
ALPHA_COMP=3  # component to use for b/w extraction

class ImageFont:
    def __init__(self, imgname, glyph_w=8, glyph_h=8):
        self.glyph_w = glyph_w
        self.glyph_h = glyph_h

        img = Image.open(imgname)

        self.chars_w = img.size[0]//glyph_w
        self.chars_h = img.size[1]//glyph_h
        self.numchars = self.chars_w * self.chars_h

        self._extract_glyphs(img)
        self._convert_to_bw()

    def _extract_glyphs(self,img):
        '''Extract RGBA glyphs'''
        data = list(img.getdata())
        self.glyphs = []
        for ch in range(self.numchars):
            basex = (ch % self.chars_w) * self.glyph_w
            basey = (ch // self.chars_w) * self.glyph_h
            baseaddr = basey*img.size[0] + basex
            glyph_data = []
            for yy in range(self.glyph_h):
                glyph_data.append(data[baseaddr:baseaddr+self.glyph_w])
                baseaddr += img.size[0]
            self.glyphs.append(glyph_data)

    def _convert_to_bw(self):
        '''Extract b/w binary glyphs'''
        self.glyphs_bw = []
        for ch in range(self.numchars):
            glyph_in = self.glyphs[ch]
            glyph_data = []
            for xx in range(self.glyph_w):
                glyph_col = 0
                for yy in range(self.glyph_h):
                    if glyph_in[yy][xx][ALPHA_COMP] >= THRESHOLD:
                        glyph_col |= 1<<yy
                glyph_data.append(glyph_col)
            self.glyphs_bw.append(glyph_data)


