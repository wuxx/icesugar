#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
核对 tb_st7735 抓到的 SPI 字节流:

  1) 初始化段: 必须和 gen_init_hex.py 的表逐字节一致 (DC 位 + 字节值)
  2) 像素段:   必须正好是 160*80*2 = 25600 字节, 且每个像素是
               "高字节在前" 的 RGB565, 颜色必须等于 8 条色条的期望值

用法: python3 chk_lcd_stream.py [spi_stream.txt]
"""
import sys
from gen_init_hex import SEQ, CMD, DAT

STREAM = sys.argv[1] if len(sys.argv) > 1 else 'spi_stream.txt'

W, H = 160, 80
BARS = [0xFFFF, 0xFFE0, 0x07FF, 0x07E0, 0xF81F, 0xF800, 0x001F, 0x0000]


def bar_color(x):
    return BARS[x // 20]


def main():
    raw = []
    total = None
    for line in open(STREAM):
        line = line.strip()
        if not line:
            continue
        if line.startswith('#'):
            total = int(line.split()[1])
            continue
        dc, byte = line.split()
        raw.append((int(dc, 2), int(byte, 16)))

    errors = []

    # ---------- 1) 初始化段 ----------
    expect = []
    for op, val in SEQ:
        if op == CMD:
            expect.append((0, val))
        elif op == DAT:
            expect.append((1, val))
        # DLY / END 不产生 SPI 字节

    got = raw[:len(expect)]
    if got != expect:
        errors.append('初始化段不匹配')
        for i, (e, g) in enumerate(zip(expect, got)):
            if e != g:
                errors.append('  第 %d 条: 期望 dc=%d byte=%02x, 实际 dc=%d byte=%02x'
                              % (i, e[0], e[1], g[0], g[1]))
                if len(errors) > 8:
                    break
        if len(raw) < len(expect):
            errors.append('  实际只有 %d 条, 期望 %d 条' % (len(raw), len(expect)))
    else:
        print('  [OK] 初始化段 %d 字节全部匹配 (命令/数据 DC 位正确)' % len(expect))

    # ---------- 2) 像素段 ----------
    pix = raw[len(expect):]
    if len(pix) != W * H * 2:
        errors.append('像素段字节数 %d != %d' % (len(pix), W * H * 2))
    else:
        bad = 0
        for i in range(W * H):
            x = i % W
            y = i // W
            dc_hi, hi = pix[2 * i]
            dc_lo, lo = pix[2 * i + 1]
            want = bar_color(x)
            if (dc_hi, dc_lo) != (1, 1) or ((hi << 8) | lo) != want:
                bad += 1
                if bad <= 5:
                    errors.append('  像素 (x=%d,y=%d): 期望 %04x, 实际 %02x%02x (dc=%d,%d)'
                                  % (x, y, want, hi, lo, dc_hi, dc_lo))
        if bad == 0:
            print('  [OK] 像素段 %d 字节 = %d 像素, 颜色全部等于 8 条色条期望值'
                  % (len(pix), W * H))
        else:
            errors.append('  %d 个像素颜色不对' % bad)

    if total is not None and total != len(raw):
        errors.append('监视器统计 %d 字节, 实际解析 %d 字节' % (total, len(raw)))

    print('  SPI 总字节数: %d (初始化 %d + 像素 %d)' % (len(raw), len(expect), len(pix)))
    if errors:
        print('FAIL')
        for e in errors:
            print(e)
        return 1
    print('PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main())
