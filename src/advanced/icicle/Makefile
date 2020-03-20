.DEFAULT_GOAL = all

QUIET    = -q
PLL      = pll.sv
SRC      = $(sort $(wildcard *.sv) $(PLL))
TOP      = top
SV       = $(TOP).sv
YS       = $(ARCH).ys
YS_ICE40 = `yosys-config --datdir/$(ARCH)/cells_sim.v`
BLIF     = $(TOP).blif
JSON     = $(TOP).json
ASC_SYN  = $(TOP)_syn.asc
ASC      = $(TOP).asc
BIN      = $(TOP).bin
SVF      = $(TOP).svf
TIME_RPT = $(TOP).rpt
STAT     = $(TOP).stat
BOARD   ?= ice40hx8k-b-evn
PROGRAM ?= hello
C_SRC    = $(filter-out programs/uip/fsdata.c, $(wildcard programs/$(PROGRAM)/*.c))
OBJ      = $(sort $(addsuffix .o, $(basename $(C_SRC))) start.o)
TARGET  ?= riscv64-unknown-elf
AS       = $(TARGET)-as
ASFLAGS  = -march=rv32i -mabi=ilp32
LD       = $(TARGET)-gcc
LDFLAGS  = $(CFLAGS) -Wl,-Tprogmem.lds
CC       = $(TARGET)-gcc
CFLAGS   = -march=rv32i -mabi=ilp32 -Wall -Wextra -pedantic -DFREQ=$(FREQ_PLL)000000 -Os -ffreestanding -nostartfiles -g -Iprograms/$(PROGRAM)
OBJCOPY  = $(TARGET)-objcopy

include boards/$(BOARD).mk
include arch/$(ARCH).mk

.PHONY: all clean syntax time stat flash

all: $(BIN)

clean:
	$(RM) $(BLIF) $(JSON) $(ASC_SYN) $(ASC) $(BIN) $(SVF) $(PLL) $(TIME_RPT) $(STAT) $(OBJ) progmem_syn.hex progmem.hex progmem.bin start.o start.s progmem progmem.lds defines.sv

progmem.bin: progmem
	$(OBJCOPY) -O binary $< $@

progmem.hex: progmem.bin
	xxd -p -c 4 < $< > $@

image:
	truncate -s 1048576 top.bin
	cat top.bin progmem.bin > icicle.bin

progmem: $(OBJ) progmem.lds
	$(LD) $(LDFLAGS) -o $@ $(OBJ)

$(BLIF) $(JSON): $(YS) $(SRC) progmem_syn.hex progmem.hex defines.sv
	yosys $(QUIET) $<

syntax: $(SRC) progmem_syn.hex defines.sv
	iverilog -D$(shell echo $(ARCH) | tr 'a-z' 'A-Z') -Wall -t null -g2012 $(YS_ICE40) $(SV)

defines.sv: boards/$(BOARD)-defines.sv
	cp boards/$(BOARD)-defines.sv defines.sv

start.s: start-$(PROGMEM).s
	cp $< $@

progmem.lds: arch/$(ARCH)-$(PROGMEM).lds
	cp $< $@

time: $(TIME_RPT)
	cat $<

stat: $(STAT)
	cat $<
