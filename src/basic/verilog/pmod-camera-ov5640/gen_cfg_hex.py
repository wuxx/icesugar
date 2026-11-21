#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 ArduCAM OV5640 寄存器表生成 iCE40 用的 $readmemh ROM (ov5640_cfg.hex)

来源: https://github.com/ArduCAM/Arduino  (ov5640_regs.h)
  OV5640YUV_Sensor_Dvp_Init : 完整初始化 (含 640x480 窗口/时序/AWB/gamma/CMX/LSC)
  ov5640_vga_preview        : 640x480@30fps 覆盖 (XCLK=24MHz, PCLK=56MHz)

输出格式 (每行 8 位十六进制 = 32bit):
    [31:30] op : 0 = 结束, 1 = 写, 2 = 读
    [29:14] 寄存器地址
    [13:6]  数据

本工程输出 **YUV422 / YUYV** (ArduCAM 初始化表的默认格式, 0x4300=0x30),
不做 RGB565 覆盖, 以便用 |U-128| 指标在硬件上判定字节序/位序。

帧率档位 (--fps):
    30 (默认原始表): 0x3035 = 0x11 -> PCLK = 56MHz, 640x480@30fps
    15             : 0x3035 = 0x21 -> PCLK = 28MHz, 640x480@15fps
  iCE40UP5K 的 fabric 实测只能跑到 ~52MHz, 而 640x480@30 的 PCLK 要 56MHz,
  因此本工程默认用 15fps 档 (余量充足), 需要 30fps 时要把字节序统计挪进 BRAM。
"""
import re, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else 'ov5640_regs.h'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'ov5640_cfg.hex'

FPS = 30
for i, a in enumerate(sys.argv):
    if a == '--fps' and i + 1 < len(sys.argv):
        FPS = int(sys.argv[i + 1])

src = open(SRC).read()


def parse(name):
    m = re.search(r'const struct sensor_reg\s+' + name + r'\[\]\s*PROGMEM\s*=\s*\{(.*?)\n\s*\};', src, re.S)
    if not m:
        raise SystemExit('table not found: ' + name)
    out = []
    for a, v in re.findall(r'\{\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)\s*\}', m.group(1)):
        a = int(a, 16)
        v = int(v, 16)
        if a == 0xffff:
            break
        out.append((a, v))
    return out


init = parse('OV5640YUV_Sensor_Dvp_Init')
prev = parse('ov5640_vga_preview')

seq = list(init) + list(prev)

# 帧率档位: 改 0x3035 的预分频 (1 -> /1 = 56MHz, 2 -> /2 = 28MHz)
if FPS == 15:
    seq.append((0x3035, 0x21))
elif FPS != 30:
    raise SystemExit('unsupported --fps %d (use 15 or 30)' % FPS)

# 同地址只保留最后一次写 (顺序保持最后出现的位置)
last = {}
for i, (a, v) in enumerate(seq):
    last[a] = (i, v)
final = [seq[i] for i in sorted(last[a][0] for a in last)]

# 关键寄存器回读 (顺序 = rd0..rd11)
#   0 0x300A  1 0x300B  芯片 ID
#   2 0x3808  3 0x3809  DVP 输出宽度
#   4 0x380A  5 0x380B  DVP 输出高度
#   6 0x4300  输出格式 (0x30 = YUV422/YUYV)
#   7 0x3017  DVP 输出/系统时钟使能
#   8 0x380C  9 0x380D  HTS
#  10 0x380E 11 0x380F  VTS
READBACK = [0x300A, 0x300B, 0x3808, 0x3809, 0x380A, 0x380B,
            0x4300, 0x3017, 0x380C, 0x380D, 0x380E, 0x380F]
#  [重要] 这 12 个回读 **不放进 ROM**。写完 271 个寄存器就立刻读 0x38xx 组
#  (输出窗口/时序寄存器)会读回 0x00 —— 相机还没把新时序吃进去; 更麻烦的是
#  这一下会把相机的 0x38xx 组"弄坏", 之后一段时间内该组的所有读都返回 0x00
#  (0x30xx / 0x43xx 组不受影响)。实测: 配置阶段只写不读, 把所有回读放到
#  顶层诊断读里(见 top.v 的 ST_DIAG0), 12 个关键寄存器就能全部读回真值。
#  ROM 里只保留写操作。


def word(op, addr, data=0):
    return ((op & 3) << 30) | ((addr & 0xFFFF) << 14) | ((data & 0xFF) << 6)


words = [word(1, a, v) for a, v in final]
words.append(word(0, 0))          # 结束标志

with open(OUT, 'w') as f:
    for w in words:
        f.write('%08x\n' % w)

print('init=%d preview=%d -> dedup=%d writes (无回读) + 1 end = %d words -> %s'
      % (len(init), len(prev), len(final), len(words), OUT))
d = dict(final)
for probe in (0x3006, 0x3008, 0x300a, 0x300b, 0x3808, 0x3809, 0x380a, 0x380b,
              0x380c, 0x380d, 0x380e, 0x380f, 0x4300, 0x4740, 0x501f):
    val = d.get(probe)
    print('  reg %04x -> %s' % (probe, ('%02x' % val) if val is not None else '(not written)'))
