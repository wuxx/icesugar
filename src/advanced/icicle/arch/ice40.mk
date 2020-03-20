PNR     ?= nextpnr
PCF      = boards/$(BOARD).pcf
ifeq ($(SPEED),up)
FREQ_PLL = 16
else
FREQ_PLL = 48
endif

progmem_syn.hex:
	icebram -g 32 2048 > $@

$(PLL):
	icepll $(QUIET) -i $(FREQ_OSC) -o $(FREQ_PLL) -m -f $@

ifeq ($(PNR),arachne-pnr)
$(ASC_SYN): $(BLIF) $(PCF)
	arachne-pnr $(QUIET) -d $(DEVICE) -P $(PACKAGE) -o $@ -p $(PCF) $<
else
$(ASC_SYN): $(JSON) $(PCF)
	nextpnr-ice40 $(QUIET) --$(SPEED)$(DEVICE) --package $(PACKAGE) --json $< --pcf $(PCF) --freq $(FREQ_PLL) --asc $@
endif

$(ASC): $(ASC_SYN) progmem_syn.hex progmem.hex
ifeq ($(PROGMEM),ram)
	icebram progmem_syn.hex progmem.hex < $< > $@
else
	cp $< $@
endif

$(BIN): $(ASC)
ifeq ($(PROGMEM),flash)
	icepack -s $< $@
else
	icepack $< $@
endif

$(TIME_RPT): $(ASC_SYN) $(PCF)
	icetime -t -m -d $(SPEED)$(DEVICE) -P $(PACKAGE) -p $(PCF) -c $(FREQ_PLL) -r $@ $<

$(STAT): $(ASC_SYN)
	icebox_stat $< > $@

flash: $(BIN) progmem.bin #$(TIME_RPT)
	icesprog $<
ifeq ($(PROGMEM),flash)
	icesprog -o 0x100000 progmem.bin
endif
