chip.bin: music.v music.pcf divide_by12.v
	yosys -q -p "synth_ice40 -blif chip.blif" music.v divide_by12.v
	arachne-pnr -d 5k -P sg48 -p music.pcf chip.blif -o chip.txt
	icepack chip.txt chip.bin

.PHONY: prog_flash
prog_flash:
	icesprog chip.bin

.PHONY: clean
clean:
	$(RM) -f chip.blif chip.txt chip.ex chip.bin
