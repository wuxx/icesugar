all: pmodoled2.bin

ICELINK_DIR=$(shell df | grep iCELink | awk '{print $$9}')
${info iCELink path: $(ICELINK_DIR)}

pmodoled2.bin: pmodoled2.v uart.v pmodoled2.pcf
	yosys -p "synth_ice40 -top top -json $(@:.bin=).json" $(filter %.v,$^)
	nextpnr-ice40 \
        --up5k \
        --package sg48 \
        --json $(@:.bin=).json \
        --pcf $(filter %.pcf,$^) \
		--asc $(@:.bin=).asc
	icepack $(@:.bin=).asc $(@:.bin=).bin

clean:
	rm -f pmodoled2.json pmodoled2.asc pmodoled2.bin

prog_flash: pmodoled2.bin
	@if [ -d '$(ICELINK_DIR)' ]; \
        then \
        cp -R pmodoled2.bin $(ICELINK_DIR); \
        else \
        echo "iCELink not found"; \
        exit 1; \
        fi

.PHONY: subdirs
.PHONY: subdirs $(SUBDIRS)
.PHONY: clean
.PHONY: prog_flash
