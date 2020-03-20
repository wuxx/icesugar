ARCH     = ice40
SPEED    = hx
DEVICE   = 8k
PACKAGE  = tq144:4k
FREQ_OSC = 100
PROGMEM  = ram

# Flash to BlackIce-II board
dfu-flash: $(BIN) $(TIME_RPT)
	dfu-util -d 0483:df11 --alt 0 --dfuse-address 0x0801F000 -D $(BIN)
