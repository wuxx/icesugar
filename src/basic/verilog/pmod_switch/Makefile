filename = pmod_switch
pcf_file = ../../../common/io.pcf

ICELINK_DIR=$(shell df | grep iCELink | awk '{print $$6}')
${warning iCELink path: $(ICELINK_DIR)}

build:
	yosys -p "synth_ice40 -json $(filename).json" $(filename).v
	nextpnr-ice40 \
		--up5k \
		--package sg48 \
		--json $(filename).json \
		--pcf $(pcf_file) \
		--asc $(filename).asc
	icepack $(filename).asc $(filename).bin

prog_flash:
	@if [ -d '$(ICELINK_DIR)' ]; \
        then \
            cp $(filename).bin $(ICELINK_DIR); \
        else \
            echo "iCELink not found"; \
            exit 1; \
    fi


clean:
	rm -rf $(filename).blif $(filename).asc $(filename).bin
