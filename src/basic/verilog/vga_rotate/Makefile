# Project setup
PROJ      = vga-rotation
DEVICE    = 5k
FOOTPRINT = sg48
YOSYS_OPTS= -noautowire # Generate errors if wires were implicitly created

# Files
FILES = top.v

.PHONY: all clean burn

all:
	# synthesize using Yosys
	yosys -ql pong.log  -p 'synth_ice40 -json top.json' top.v
	# Place and route using arachne
	nextpnr-ice40 --up5k --package sg48 --freq 13 --json top.json --pcf pinmap.pcf --asc top.asc
	icetime -c 13 -d up5k -mtr top.rpt top.asc
	# Convert to bitstream using IcePack
	icepack top.asc top.bin

prog_flash: all
	icesprog top.bin

clean:
	rm *.asc *.rpt *.json *.log *.bin
