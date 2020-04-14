filename = pll_uart_mirror
pcf_file = ../../../common/io.pcf

ICELINK_DIR=$(shell df | grep iCELink | awk '{print $$6}')
${warning iCELink path: $(ICELINK_DIR)}

build:
	yosys -p "synth_ice40 -blif $(filename).blif" $(filename).v
	#yosys -p 'synth_ice40 -top top -json pll_uart_mirror.json' pll_uart_mirror.v
	arachne-pnr -d 5k -P sg48 -p $(pcf_file) $(filename).blif -o $(filename).asc
	#nextpnr-ice40 --up5k --json pll_uart_mirror.json --pcf $(pcf_file) --asc pll_uart_mirror.asc
	icepack $(filename).asc $(filename).bin

prog_flash:
	@if [ -d '$(ICELINK_DIR)' ]; \
        then \
            cp $(filename).bin $(ICELINK_DIR); \
        else \
            echo "iCELink not found, exit"; \
            exit 1; \
    fi


clean:
	rm -rf $(filename).blif $(filename).asc $(filename).bin
