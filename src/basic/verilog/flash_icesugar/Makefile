filename = control
pcf_file = common/io.pcf

clean:
	rm .sconsign.dblite *.out *.vcd

build:
	yosys -p "synth_ice40 -json bin/$(filename).json" $(filename).v
	nextpnr-ice40 \
		--up5k \
		--package sg48 \
		--json bin/$(filename).json \
		--pcf $(pcf_file) \
		--asc bin/$(filename).asc
	icepack bin/$(filename).asc bin/$(filename).bin

sim:
	apio sim
	make clean
