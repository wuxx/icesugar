chip.bin: music.v music.pcf
	yosys -p "synth_ice40 -blif chip.blif" music.v
	arachne-pnr -d 5k -P sg48 -p music.pcf chip.blif -o chip.txt
	icepack chip.txt chip.bin

.PHONY: prog_flash
prog_flash:
	icesprog chip.bin

.PHONY: clean
clean:
	$(RM) -f chip.blif chip.txt chip.ex chip.bin
