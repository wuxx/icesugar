#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 uart_printer 用的文本模板 text.hex (每行 1 字节)

转义序列 (与 uart_printer.v 一致):
   0x01 <idx>  vars[idx]  -> 2 位十六进制
   0x02 <idx>  vars[idx]  -> 十进制
   0x03 <idx>  vars[idx]  -> 8 位十六进制
   0x04 <idx>  vars[idx]!=0 -> "OK" 否则 "FAIL"
   0x05 <idx>  samples[idx] -> 2 位十六进制
   0x00        结束

vars 索引 (与 top.v 对应):
   0  0x0A 芯片 ID PID (期望 0x26)  1  0x0B 芯片 ID VER (期望 0x42)
   2  SCCB 无应答事务数            3  DVP 输出宽度(像素, DVP 实测)
   4  0xC1 VSIZE8 (height>>3)      5  DVP 输出高度(行/帧, DVP 实测)
   6  0x51 HSIZE (窗口)            7  PCLK MHz
   8  帧数                        9  每帧行数
   10 每行字节数                  11 fps
   12 有效字节数                  13..16 四种字节序假设的指标
   17 结论位图                    18 SCCB 链路结论
   19 DVP 链路结论                20 字节序结论
   21 XMCLK MHz                   22 VSYNC 计数
   23 最小的字节序指标            24 地址探测命中位图
   25 选定的从机地址字节          26 总线空闲时 SDA 电平
   27 累计应答次数                28 0xDA IMAGE_MODE (0x00=YUV422/YUYV)
   29 0xC2 CTRL0 (0x0E)            30 HSIZE8/VSIZE8 合成 16 位
   31 HSIZE8 (width>>3)           32 HSIZE/VSIZE 合成 16 位
   33 VSIZE (窗口)                34 应答检查总次数
   35 其中没应答的次数            36 参与字节序统计的字节数
   37 VSYNC 跳变次数              38 HREF 跳变次数
   39 读成功次数                  40 写成功次数
   41 相机拉低 SDA 的周期数       42 SCL 引脚检查通过
   43 SDA 引脚检查通过            44 应答窗口 SCL 回读异常次数
   45 数据线跳变位图              46 冻结瞬间数据线电平
   47 采样字节最小值              48 采样字节最大值
   49 DSP bank 里读到非零的个数     50 诊断读里有几次没应答
   51 0xC0 HSIZE8 回读值          52 0xC1 VSIZE8 回读值
   53 0x5A ZMOW 回读值
"""
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else 'text.hex'

buf = bytearray()


def s(text):
    buf.extend(text.encode('ascii'))


def hex8(i):
    buf.append(0x01); buf.append(i)


def dec(i):
    buf.append(0x02); buf.append(i)


def hex32(i):
    buf.append(0x03); buf.append(i)


def okf(i):
    buf.append(0x04); buf.append(i)


def samp(i):
    buf.append(0x05); buf.append(i)


s("OV2640 DVP TEST  --  iCE40UP5K / iCESugar\r\n")
s("=====================================================\r\n")
s("[SCCB LINK PROBE]\r\n")
s("  sda idle = "); hex8(26); s(" (1=pull-up ok)  scl idle = "); hex8(54); s("  addr mask=0x"); hex8(24)
s(" (b0=60 b1=30 b2=D8 b3=6C b4=20 b5=50)\r\n")
s("  chosen addr=0x"); hex8(25); s("  acks="); dec(27); s("  failed="); dec(35); s("\r\n")
s("  pin check: sda="); okf(43); s(" scl="); okf(42); s("   cam pulled SDA="); dec(41)
s(" cycles   scl mismatch="); dec(44); s("\r\n")
s("\r\n")
s("[SCCB READBACK]\r\n")
s("  chip id 0x0A=0x"); hex8(0); s(" 0x0B=0x"); hex8(1); s("  (expect 26/42)\r\n")
s("  dvp size (measured) "); hex32(3); s(" x "); hex32(5); s("   IMAGE_MODE=0x"); hex8(28); s("  CTRL0=0x"); hex8(29); s("\r\n")
s("  HSIZE8/VSIZE8=0x"); hex32(30); s("  (expect C896)   HSIZE/VSIZE=0x"); hex32(32); s(" (expect 902C)\r\n")
s("  DSP bank readback: nonzero="); dec(49); s("/8   raw 0xC0=0x"); hex8(51)
s(" 0xC1=0x"); hex8(52); s(" 0x5A(ZMOW)=0x"); hex8(53); s(" 0x51(HSIZE)=0x"); hex8(6); s("\r\n")
s("  sensor bank: GAIN(0x00)=0x"); hex8(4); s("  AEC(0x10)=0x"); hex8(31); s("\r\n")
s("  diag nack="); dec(50); s("\r\n")
s("  reads ok="); dec(39); s("/12  writes ok="); dec(40); s("  nack tx="); dec(2); s("\r\n")
s("  sccb link = "); okf(18); s("\r\n")
s("\r\n")
s("[DVP]\r\n")
s("  pclk = "); dec(7); s(" MHz  (OV2640: sysclk / R_DVP_SP)\r\n")
s("  frames="); dec(8); s(" lines/frame="); dec(9); s(" bytes/line="); dec(10); s(" fps="); dec(11); s("\r\n")
s("  active bytes="); dec(12); s(" vsync="); dec(22); s(" xclk="); dec(21); s("MHz\r\n")
s("  vsync edges="); dec(37); s(" href edges="); dec(38); s(" metric bytes="); dec(36); s("\r\n")
s("  data pins changed=0x"); hex8(45); s(" now=0x"); hex8(46)
s("  byte min=0x"); hex8(47); s(" max=0x"); hex8(48); s("\r\n")
s("  line period="); dec(55); s(" pclk cycles   frame period="); dec(56); s(" pclk cycles\r\n")
s("  dvp link = "); okf(19); s("\r\n")
s("\r\n")
s("[BYTE ORDER] sum |byte-128| over chroma bytes (smaller = better)\r\n")
s("  chroma-odd  normal = "); dec(13); s("\r\n")
s("  chroma-even normal = "); dec(14); s("\r\n")
s("  chroma-odd  bitrev = "); dec(15); s("\r\n")
s("  chroma-even bitrev = "); dec(16); s("\r\n")
s("  best = "); dec(23); s("\r\n")
s("  order = "); okf(20); s("\r\n")
s("\r\n")
s("first 16 bytes: ")
for i in range(16):
    samp(i); s(" ")
s("\r\n")
s("verdict = "); dec(17); s(" (bit0 sccb_ok, bit1 dvp_ok, bit2 order_ok,")
s(" bit3 normal-bits, bit4 chroma-odd)\r\n")
s("END\r\n")
buf.append(0x00)

with open(OUT, 'w') as f:
    for b in buf:
        f.write('%02x\n' % b)

print('text bytes = %d -> %s' % (len(buf), OUT))
