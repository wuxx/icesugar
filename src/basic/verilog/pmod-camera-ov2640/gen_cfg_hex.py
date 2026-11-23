#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 OV2640 寄存器表生成 iCE40 用的 $readmemh ROM (ov2640_cfg.hex)

来源: Linux 内核 drivers/media/i2c/ov2640.c
      ov2640_init_regs + ov2640_size_change_preamble_regs + ov2640_vga_regs
      + ov2640_format_change_preamble_regs + ov2640_yuyv_regs
      (本仓库的 ov2640_regs.h 已经把它们整理成下面几张表)

输出格式 (每行 8 位十六进制 = 32bit):
    [31:30] op : 0 = 结束, 1 = 写, 2 = 读, 3 = 延时(毫秒)
    [29:14] 寄存器地址
    [13:6]  数据

注意 (相对 OV5640 的 gen_cfg_hex.py):
  1) **不做同地址去重**。OV2640 的 0xFF 是 bank 选择寄存器, 同一个地址在不同
     bank 下是完全不同的寄存器, 而且 BPDATA(0x7D) 连续写时靠的是芯片内部的
     地址自增 —— 一旦合并顺序就会写坏。所以这里严格按表里的顺序原样输出。
  2) 寄存器地址是 8 位 (OV5640 是 16 位 0x3xxx), 由 sccb_master 的 ADDR8 模式
     处理。
  3) 表里可以用伪地址 0xFF00 表示"延时 N 毫秒"。
"""
import re
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else 'ov2640_regs.h'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'ov2640_cfg.hex'

# 严格按这个顺序拼, 不能换: bank 切换靠前面的 0xFF 写
TABLES = [
    'ov2640_reset_regs',
    'ov2640_init_regs',
    'ov2640_size_preamble_regs',
    'ov2640_vga_regs',
    'ov2640_format_preamble_regs',
    'ov2640_yuyv_regs',
    'ov2640_end_regs',
]

OP_END, OP_W, OP_R, OP_DELAY = 0, 1, 2, 3
PSEUDO_DELAY = 0xFF00

src = open(SRC, encoding='utf-8').read()


def parse(name):
    m = re.search(r'const struct sensor_reg\s+' + name + r'\[\]\s*PROGMEM\s*=\s*\{(.*?)\n\};',
                  src, re.S)
    if not m:
        raise SystemExit('table not found: ' + name)
    body = m.group(1)
    out = []
    for a, v in re.findall(r'\{\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)\s*\}', body):
        out.append((int(a, 16), int(v, 16)))
    #  数组里一共写了几个 {0xNN, 0xNN}? 正则只认十六进制, 写成十进制会被漏掉 ->
    #  数目对不上就报错, 避免整张表静默少写几条。
    n_braces = body.count('{')
    if n_braces != len(out):
        raise SystemExit('table %s: 写了 %d 项, 但只解析出 %d 项 '
                         '(值必须写成 0x 十六进制)' % (name, n_braces, len(out)))
    return out


def word(op, addr, data=0):
    return ((op & 3) << 30) | ((addr & 0xFFFF) << 14) | ((data & 0xFF) << 6)


words = []
counts = []
total_delay = 0
n_delay = 0
for name in TABLES:
    seq = parse(name)
    counts.append((name, len(seq)))
    for a, v in seq:
        if a == PSEUDO_DELAY:
            words.append(word(OP_DELAY, 0, v))
            total_delay += v
            n_delay += 1
        else:
            words.append(word(OP_W, a, v))

#  延时是"软复位后等芯片复位完成"的关键, 少一条就静默失效 -> 必须显式检查
if n_delay < 1:
    raise SystemExit('表里没有延时指令(地址 0x%04X): 软复位后必须等芯片复位完成'
                     % PSEUDO_DELAY)

words.append(word(OP_END, 0))

if len(words) > 512:
    raise SystemExit('ROM too long: %d words (max 512)' % len(words))

with open(OUT, 'w') as f:
    for w in words:
        f.write('%08x\n' % w)

for name, n in counts:
    print('  %-32s %4d' % (name, n))
print('total = %d words (writes/delays) + 1 end -> %s' % (len(words), OUT))
print('total delay = %d ms' % total_delay)

# 打印几个关键寄存器的最终值, 方便和 README 对照
last = {}
for name in TABLES:
    for a, v in parse(name):
        if a != PSEUDO_DELAY:
            last[a] = v
print('  key regs: HSIZE8(0xC0)=0x%02x VSIZE8(0xC1)=0x%02x SIZEL(0x8C)=0x%02x' %
      (last.get(0xC0, 0), last.get(0xC1, 0), last.get(0x8C, 0)))
print('  key regs: ZMOW(0x5A)=0x%02x ZMOH(0x5B)=0x%02x IMAGE_MODE(0xDA)=0x%02x CTRL0(0xC2)=0x%02x' %
      (last.get(0x5A, 0), last.get(0x5B, 0), last.get(0xDA, 0), last.get(0xC2, 0)))
print('  key regs: COM7(0x12)=0x%02x CLKRC(0x11)=0x%02x R_DVP_SP(0xD3)=0x%02x REG04(0x04)=0x%02x' %
      (last.get(0x12, 0), last.get(0x11, 0), last.get(0xD3, 0), last.get(0x04, 0)))
