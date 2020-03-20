LPF      = boards/$(BOARD).lpf
FREQ_PLL = 80

progmem_syn.hex:
	touch $@

$(PLL):
	ecppll -i $(FREQ_OSC) -o $(FREQ_PLL) -f $@

$(ASC_SYN): $(JSON) $(LPF)
	nextpnr-ecp5 $(QUIET) --$(DEVICE) --speed $(SPEED) --package $(PACKAGE) --json $< --lpf $(LPF) --freq $(FREQ_PLL) --textcfg $@

$(ASC): $(ASC_SYN) progmem_syn.hex progmem.hex
	cp $< $@

$(BIN) $(SVF): $(ASC)
	ecppack --svf $(SVF) $< $@

$(TIME_RPT):
	touch $@

$(STAT):
	touch $@

flash: $(SVF) $(TIME_RPT)
	openocd -f boards/$(BOARD)-openocd.cfg -c 'transport select jtag; init; svf $<; exit'
