#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 ST7735 初始化 ROM (st7735_init.hex), 每行 16bit。

    [15:14] op : 0=命令 1=数据 2=延时(低 8 位 = 毫秒) 3=结束
    [7:0]   字节

初始化顺序照抄 iceZ0mb1e 参考固件 firmware/main/main_st7735.c 的 tft_init(),
该工程在 iCESugar + 同一块 0.96" ST7735S 模块上验证可用, 所以这里不做任何
"优化", 只把 C 的调用序列翻译成 ROM。

参考固件里窗口是这么写的 (tft_set_addr_window):
    列 = x + 1      (横屏 160 宽 -> 列 1..160)
    行 = y + 26     (横屏  80 高 -> 行 26..105)
所以 ROM 末尾的窗口命令用 0x2A: 1..160, 0x2B: 26..105。
"""
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else 'st7735_init.hex'

CMD, DAT, DLY, END = 0, 1, 2, 3

# ---------------------------------------------------------------------------
#  初始化序列 (顺序不能改)
# ---------------------------------------------------------------------------
SEQ = [
    (CMD, 0x11),                                   # SLPOUT  (退出休眠)
    (DLY, 120),                                    # SLPOUT 后必须等 120ms

    # 帧率 / 电源
    (CMD, 0xB1), (DAT, 0x05), (DAT, 0x3C), (DAT, 0x3C),
    (CMD, 0xB2), (DAT, 0x05), (DAT, 0x3C), (DAT, 0x3C),
    (CMD, 0xB3), (DAT, 0x05), (DAT, 0x3C), (DAT, 0x3C),
                (DAT, 0x05), (DAT, 0x3C), (DAT, 0x3C),
    (CMD, 0xB4), (DAT, 0x03),
    (CMD, 0xC0), (DAT, 0xAB), (DAT, 0x0B), (DAT, 0x04),
    (CMD, 0xC1), (DAT, 0xC5),
    (CMD, 0xC2), (DAT, 0x0D), (DAT, 0x00),
    (CMD, 0xC3), (DAT, 0x8D), (DAT, 0x6A),
    (CMD, 0xC4), (DAT, 0x8D), (DAT, 0xEE),
    (CMD, 0xC5), (DAT, 0x0F),

    # Gamma 校正
    (CMD, 0xE0), (DAT, 0x07), (DAT, 0x0E), (DAT, 0x08), (DAT, 0x07),
                (DAT, 0x10), (DAT, 0x07), (DAT, 0x02), (DAT, 0x07),
                (DAT, 0x09), (DAT, 0x0F), (DAT, 0x25), (DAT, 0x36),
                (DAT, 0x00), (DAT, 0x08), (DAT, 0x04), (DAT, 0x10),
    (CMD, 0xE1), (DAT, 0x0A), (DAT, 0x0D), (DAT, 0x08), (DAT, 0x07),
                (DAT, 0x0F), (DAT, 0x07), (DAT, 0x02), (DAT, 0x07),
                (DAT, 0x09), (DAT, 0x0F), (DAT, 0x25), (DAT, 0x35),
                (DAT, 0x00), (DAT, 0x09), (DAT, 0x04), (DAT, 0x10),

    (CMD, 0xFC), (DAT, 0x80),                     # PVGAMCTRL

    (CMD, 0x3A), (DAT, 0x05),                     # COLMOD = 16bit/pixel
    (CMD, 0x36), (DAT, 0x78),                     # MADCTL: 横屏 + RGB
    (CMD, 0x21),                                  # INVON  (反色)
    (CMD, 0x29),                                  # DISPON (开显示)

    # 地址窗口 (横屏 160x80, GRAM 偏移 列+1 行+26)
    (CMD, 0x2A), (DAT, 0x00), (DAT, 0x01), (DAT, 0x00), (DAT, 0xA0),
    (CMD, 0x2B), (DAT, 0x00), (DAT, 0x1A), (DAT, 0x00), (DAT, 0x69),
    (CMD, 0x2C),                                  # RAMWR: 之后开始写像素
    (DLY, 100),

    (END, 0),
]

MAX_ROM = 128          # RTL 里 reg [15:0] rom [0:127]


def word(op, val):
    return ((op & 3) << 14) | (val & 0xFF)


def main():
    words = [word(op, val) for op, val in SEQ]
    if len(words) > MAX_ROM:
        raise SystemExit('ROM 太长: %d 条 (上限 %d)' % (len(words), MAX_ROM))

    n_cmd = sum(1 for op, _ in SEQ if op == CMD)
    n_dat = sum(1 for op, _ in SEQ if op == DAT)
    n_dly = sum(1 for op, _ in SEQ if op == DLY)

    #  补齐到 MAX_ROM (多余的填 END), 否则 $readmemh 会报
    #  "Not enough words in the file for the requested range"
    words += [word(END, 0)] * (MAX_ROM - len(words))

    with open(OUT, 'w') as f:
        for w in words:
            f.write('%04x\n' % w)

    print('  命令 %d 条, 数据 %d 条, 延时 %d 处' % (n_cmd, n_dat, n_dly))
    print('  有效 %d 条, 补齐到 %d 条 -> %s' % (len(SEQ), MAX_ROM, OUT))


if __name__ == '__main__':
    main()
