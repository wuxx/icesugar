chip.bin: music.v music.pcf
	yosys -q -p "synth_ice40 -blif chip.blif" music.v
	arachne-pnr -d 5k -P sg48 -p music.pcf chip.blif -o chip.txt
	icepack chip.txt chip.bin

.PHONY: upload
upload:
	cat chip.bin >/dev/ttyUSB0

.PHONY: clean
clean:
	$(RM) -f chip.blif chip.txt chip.ex chip.bin
