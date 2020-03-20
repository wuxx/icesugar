#!/bin/bash

#write a simple hex to the flash with an offset of 1MB (starts at 0x100000)
#iceprog -o 1M -n prog.hex

icesprog -o 0x100000 prog.bin
