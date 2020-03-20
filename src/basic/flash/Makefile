filename = top
pcf_file = ../../common/io.pcf

build:
	yosys -p "synth_ice40 -blif $(filename).blif" $(filename).v
	arachne-pnr -d 5k -P sg48 -p $(pcf_file) $(filename).blif -o $(filename).asc
	icepack $(filename).asc $(filename).bin

#prog: #for sram, not useful to read flash
#	iceprog -S $(filename).bin

prog:
	icesprog $(filename).bin

clean:
	rm -rf $(filename).blif $(filename).asc $(filename).bin
