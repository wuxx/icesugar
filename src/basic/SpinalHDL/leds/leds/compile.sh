#!/bin/sh
yosys -p "synth_ice40 -blif Test.blif"  Test.v
arachne-pnr -d 5k -P sg48 -p Test.pcf Test.blif -o Test.asc
icepack Test.asc Test.bin
    
