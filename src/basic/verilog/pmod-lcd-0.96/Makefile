PROJ = top
PIN_DEF = top.pcf
DEVICE = up5k
PACKAGE = sg48
FREQ = 24
ADD_SRC = st7735.v

ICELINK_DIR=$(shell df | grep iCELink | awk '{print $$6}')
${warning iCELink path: $(ICELINK_DIR)}

all: $(PROJ).bin $(PROJ).rpt

# ---- 初始化 ROM ----
st7735_init.hex: gen_init_hex.py
	python3 gen_init_hex.py $@

# ---- 综合 / 布线 / 打包 ----
%.json: $(PROJ).v $(ADD_SRC) st7735_init.hex
	yosys -ql $*.log -p 'synth_ice40 -json $@' $(PROJ).v $(ADD_SRC)
	@if grep -q -e "multiple conflicting drivers" -e "Driver-driver conflict" $*.log; then \
	    echo "ERROR: yosys 报 multiple conflicting drivers —— 有信号被解析成常量, 逻辑已经失效"; \
	    grep -n -e "multiple conflicting drivers" -e "Driver-driver conflict" $*.log; \
	    exit 1; \
	fi

%.asc: %.json $(PIN_DEF)
	nextpnr-ice40 --$(DEVICE) $(if $(PACKAGE),--package $(PACKAGE)) $(if $(FREQ),--freq $(FREQ)) --json $< --pcf $(PIN_DEF) --asc $@

%.bin: %.asc
	icepack $< $@

%.rpt: %.asc
	icetime $(if $(FREQ),-c $(FREQ)) -d $(DEVICE) -mtr $@ $<

# 拖拽烧录 (iCELink 虚拟 U 盘)
prog_flash:
	@if [ -d '$(ICELINK_DIR)' ]; \
        then \
            cp $(PROJ).bin $(ICELINK_DIR); \
        else \
            echo "iCELink not found"; \
            exit 1; \
    fi

# 命令行烧录 (iCELink HID, 需要板子接在跑这个脚本的机器上)
prog_icesprog:
	../../../tools/src/icesprog $(PROJ).bin

# 离线仿真 (不需要硬件): 抓 SPI 上的字节流, 逐字节核对初始化序列和色条数据
sim: tb_st7735.vvp
	vvp tb_st7735.vvp
	python3 chk_lcd_stream.py spi_stream.txt

tb_st7735.vvp: tb_st7735.v st7735.v st7735_init.hex
	iverilog -g2005 -o $@ tb_st7735.v st7735.v

clean:
	rm -f $(PROJ).blif $(PROJ).asc $(PROJ).rpt $(PROJ).bin $(PROJ).json $(PROJ).log
	rm -f st7735_init.hex
	rm -f tb_st7735.vvp spi_stream.txt

.SECONDARY:
.PHONY: all prog_flash prog_icesprog sim clean
