PROJ = top
PIN_DEF = top.pcf
DEVICE = up5k
PACKAGE = sg48
FREQ = 24
ADD_SRC = sccb_master.v ov5640_cfg.v dvp_capture.v uart_tx.v uart_printer.v

# 拍照模式: 独立入口 top_photo (OV5640 -> 串口 -> PC 端拼 PNG)
#  不影响上面 make 的默认流程, 单独用 "make photo" 构建
PHOTO_SRC = sccb_master.v ov5640_cfg.v dvp_linebuf.v photo_tx.v uart_tx.v

# 串口波特率 (必须和主机端串口设置一致)
#  115200 = 稳 (DAPLink 侧 0.16% 波特率误差); 460800 在 48MHz 时钟下误差 7~8%, 收不到
PHOTO_BAUD ?= 115200

# 行缓冲大小 (KROWS 行 x LINEB 字节, 用 BRAM 双口存)
PHOTO_KROWS ?= 8
PHOTO_LINEB ?= 1280

# 额外编译宏 (例如 PHOTO_EXTRA=-DPHOTO_MINIMAL 做一个不带行缓冲的最小验证版)
PHOTO_EXTRA ?=

# 相机帧率档位: 15 -> PCLK 28MHz (fabric 跑得动) / 30 -> PCLK 56MHz (需要重做字节序统计)
FPS ?= 15

ICELINK_DIR=$(shell df | grep iCELink | awk '{print $$6}')
${warning iCELink path: $(ICELINK_DIR)}

all: $(PROJ).bin $(PROJ).rpt

# ---- 拍照模式 ----
photo: top_photo.bin top_photo.rpt

top_photo.json: top_photo.v $(PHOTO_SRC) ov5640_cfg.hex
	yosys -ql top_photo.log -DPHOTO_BAUD=$(PHOTO_BAUD) -DPHOTO_KROWS=$(PHOTO_KROWS) -DPHOTO_LINEB=$(PHOTO_LINEB) $(PHOTO_EXTRA) -p 'synth_ice40 -json $@' top_photo.v $(PHOTO_SRC)

top_photo.asc: top_photo.json top_photo.pcf
	nextpnr-ice40 --$(DEVICE) $(if $(PACKAGE),--package $(PACKAGE)) $(if $(FREQ),--freq $(FREQ)) --json $< --pcf top_photo.pcf --asc $@

top_photo.bin: top_photo.asc
	icepack $< $@

top_photo.rpt: top_photo.asc
	icetime $(if $(FREQ),-c $(FREQ)) -d $(DEVICE) -mtr $@ $<

# ---- 寄存器表 / 文本模板 ----
ov5640_cfg.hex: gen_cfg_hex.py ov5640_regs.h
	python3 gen_cfg_hex.py ov5640_regs.h $@ --fps $(FPS)

text.hex: gen_text_hex.py
	python3 gen_text_hex.py $@

# ---- 综合 / 布线 / 打包 ----
%.json: $(PROJ).v $(ADD_SRC) ov5640_cfg.hex text.hex
	yosys -ql $*.log -p 'synth_ice40 -json $@' $(PROJ).v $(ADD_SRC)

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

# 命令行烧录 (iCELink HID)
prog_icesprog:
	../../../tools/src/icesprog $(PROJ).bin

# 离线仿真报表展开 (iverilog, 不需要硬件)
# 用真实的 text.hex 跑一遍 uart_printer, 输出在 sim_out.txt
sim:
	iverilog -g2005 -o tb_printer.vvp tb_printer.v uart_printer.v uart_tx.v
	vvp tb_printer.vvp
	@echo "==== sim_out.txt ===="
	@cat sim_out.txt

# 拍照模式的离线仿真 (不接硬件)
#   tb_linebuf : 合成 DVP 流, 检查"到底抓到了哪几行"
#   tb_photo   : 把串口字节流还原出来, 和主机端算法逐字节比对
sim_photo: tb_linebuf.vvp tb_photo.vvp
	vvp tb_linebuf.vvp
	vvp tb_photo.vvp
	python3 chk_photo.py sim_photo.hex

tb_linebuf.vvp: tb_linebuf.v dvp_linebuf.v
	iverilog -g2005 -o $@ $^

tb_photo.vvp: tb_photo.v photo_tx.v uart_tx.v
	iverilog -g2005 -o $@ $^

clean:
	rm -f $(PROJ).blif $(PROJ).asc $(PROJ).rpt $(PROJ).bin $(PROJ).json $(PROJ).log
	rm -f tb_printer.vvp sim_out.txt sim_trace.txt
	rm -f top_photo.blif top_photo.asc top_photo.rpt top_photo.bin top_photo.json top_photo.log
	rm -f tb_linebuf.vvp tb_photo.vvp sim_photo.hex sim_top.hex

.SECONDARY:
.PHONY: all photo prog_flash prog_icesprog sim sim_photo clean
