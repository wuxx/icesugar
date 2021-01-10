filename = hard_led
pcf_file = ../../../common/io.pcf

ICELINK_DIR=$(shell df | grep iCELink | awk '{print $$6}')
${warning iCELink path: $(ICELINK_DIR)}


$(filename).bin: $(filename).asc
	icepack $(filename).asc $(filename).bin

$(filename).asc: $(filename).json
	nextpnr-ice40 \
		--up5k \
		--package sg48 \
		--json $(filename).json \
		--pcf $(pcf_file) \
		--asc $(filename).asc

$(filename).json: $(filename).v
	yosys -p "synth_ice40 -top $(filename) -json $(filename).json" $(filename).v


prog_flash:
	@if [ -d '$(ICELINK_DIR)' ]; \
     	then \
		cp $(filename).bin $(ICELINK_DIR); \
     	else \
		echo "iCELink not found"; \
		exit 1; \
     	fi

clean:
	rm -rf $(filename).json $(filename).asc $(filename).bin
