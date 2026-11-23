#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""host_capture.py -- 接收 iCESugar(OV5640) 拍照固件发来的图像行包, 拼成 PNG。

FPGA 端每行发一个包:
    A5 5A | row(2, LE) | len(2, LE) | data[len] | crc(2, LE)
CRC = CRC16/CCITT-FALSE, 覆盖 "包头4字节 + 本行数据", magic 不参与计算。

用法:
    python host_capture.py                       # 只收, 不烧录
    python host_capture.py --flash               # 先烧 top_photo.bin 再收
    python host_capture.py --baud 115200         # 换波特率
    python host_capture.py --seconds 90          # 收多久

输出:
    photo.raw    拼好的原始 YUYV (640*480*2 字节, 缺行填 0x80)
    photo.png    转成 RGB 的 PNG
"""
import argparse
import os
import subprocess
import sys
import time

import serial
from serial.tools import list_ports

WS = os.environ.get('ICESP_DIR') or os.path.dirname(os.path.abspath(__file__))
ICESPROG = os.environ.get('ICESPROG') or os.path.join(WS, 'icesprog.exe')

WIDTH = 640
HEIGHT = 480
LINEB = WIDTH * 2          # YUYV, 每行 1280 字节
MAGIC = b'\xa5\x5a'


def crc16_ccitt_false(data, crc=0xFFFF):
    """CRC16/CCITT-FALSE: poly 0x1021, init 0xFFFF, MSB first, no final xor."""
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def find_port():
    for p in list_ports.comports():
        if p.vid == 0x1D50 and p.pid == 0x602B:
            return p.device
    return None


def yuyv_to_rgb(buf, width, height):
    """YUYV (Y0 U Y1 V ...) -> RGB uint8 三通道数组。

    字节序: Y0 U0 Y1 V0 Y2 U1 Y3 V1 ...
      - Y 在偶数位, 每像素一个      -> a[:, 0::2]   (640 个)
      - U/V 每 2 个像素共享一个采样 -> a[:, 1::4] / a[:, 3::4] (320 个)
    所以 U/V 取出来要用 np.repeat(..., 2) 复制回每像素一个, 否则宽度对不上。
    """
    import numpy as np
    a = np.frombuffer(buf, dtype=np.uint8)
    n = width * height
    if a.size < n * 2:
        a = np.concatenate([a, np.full(n * 2 - a.size, 0x80, np.uint8)])
    a = a[:n * 2].reshape(height, width * 2)
    y = a[:, 0::2].astype(np.float32)
    u = np.repeat(a[:, 1::4], 2, axis=1).astype(np.float32)
    v = np.repeat(a[:, 3::4], 2, axis=1).astype(np.float32)

    c = y - 16.0
    d = u - 128.0
    e = v - 128.0
    r = 1.164 * c + 1.596 * e
    g = 1.164 * c - 0.392 * d - 0.813 * e
    b = 1.164 * c + 2.017 * d
    out = np.zeros((height, width, 3), np.uint8)
    out[:, :, 0] = np.clip(r, 0, 255).astype(np.uint8)
    out[:, :, 1] = np.clip(g, 0, 255).astype(np.uint8)
    out[:, :, 2] = np.clip(b, 0, 255).astype(np.uint8)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--flash', action='store_true', help='先烧录 top_photo.bin')
    ap.add_argument('--bin', default=os.path.join(WS, 'top_photo.bin'))
    ap.add_argument('--baud', type=int, default=115200)
    ap.add_argument('--seconds', type=float, default=120.0)
    ap.add_argument('--out', default=os.path.join(WS, 'photo'))
    ap.add_argument('--no-png', action='store_true')
    args = ap.parse_args()

    if args.flash:
        print('--- flash %s ---' % args.bin, flush=True)
        r = subprocess.run([ICESPROG, args.bin], capture_output=True, text=True)
        print((r.stdout or '').strip())
        print('icesprog exit=%d' % r.returncode, flush=True)
        time.sleep(1.5)

    port = None
    for _ in range(40):
        port = find_port()
        if port:
            break
        time.sleep(0.25)
    if port is None:
        print('ICELINK_CDC_NOT_FOUND')
        sys.exit(1)
    print('PORT=%s baud=%d' % (port, args.baud), flush=True)

    ser = serial.Serial(port, args.baud, timeout=0.02)

    rows = {}
    buf = bytearray()
    rawstream = bytearray()
    total = 0
    good = 0
    badcrc = 0
    resync = 0

    t0 = time.time()
    last_report = t0
    while time.time() - t0 < args.seconds:
        try:
            d = ser.read(2048)
        except Exception as e:
            print('READ ERROR: %r' % e, flush=True)
            break
        if not d:
            continue
        total += len(d)
        buf.extend(d)
        rawstream.extend(d)

        # ---- 解析 ----
        while True:
            # 找 magic
            i = buf.find(MAGIC)
            if i < 0:
                # 保留最后一个字节, 防止 A5 5A 被截断
                if len(buf) > 1:
                    del buf[:-1]
                break
            if i > 0:
                resync += 1
                del buf[:i]
            if len(buf) < 8:
                break
            row = buf[2] | (buf[3] << 8)
            ln = buf[4] | (buf[5] << 8)
            if ln == 0 or ln > 4096:
                # 长度不对 -> 这不是真的包头, 跳过这个 magic 继续找
                badcrc += 1
                del buf[:1]
                continue
            if len(buf) < 8 + ln:
                break                       # 数据还没到齐
            payload = bytes(buf[2:6]) + bytes(buf[6:6 + ln])
            crc_rx = buf[6 + ln] | (buf[7 + ln] << 8)
            if crc16_ccitt_false(payload) != crc_rx:
                badcrc += 1
                del buf[:1]                # 丢一个字节重新同步
                continue
            del buf[:8 + ln]
            good += 1
            if row == 0xFFFF:
                # 状态包 (遥测): byte0=诊断码 byte1=flags byte2=段号
                #                byte4-5=已采行数 byte6-9=已采字节 byte10-11=末行字节
                if ln >= 12:
                    code = payload[4]
                    flags = payload[5]
                    segno = payload[6]
                    lines = payload[8] | (payload[9] << 8)
                    nbytes = (payload[10] | (payload[11] << 8) |
                              (payload[12] << 16) | (payload[13] << 24))
                    rowb = payload[14] | (payload[15] << 8)
                    print('  [STAT] code=%d flags=0x%02x seg=%d lines=%d bytes=%d rowbytes=%d'
                          % (code, flags, segno, lines, nbytes, rowb), flush=True)
            elif row not in rows:
                rows[row] = bytes(payload[4:])   # payload 前 4 字节是包头

        if time.time() - last_report > 5:
            last_report = time.time()
            print('  %.1fs  bytes=%d  ok=%d  bad=%d  rows=%d/480'
                  % (time.time() - t0, total, good, badcrc, len(rows)), flush=True)
        if len(rows) >= HEIGHT:
            print('  got all %d rows' % HEIGHT, flush=True)
            break

    ser.close()

    missing = [r for r in range(HEIGHT) if r not in rows]
    print('---- summary ----', flush=True)
    print('elapsed  = %.1fs' % (time.time() - t0))
    print('bytes    = %d' % total)
    print('packets  = %d (crc ok)  %d (bad crc / resync)' % (good, badcrc))
    print('rows     = %d / %d' % (len(rows), HEIGHT))
    if missing:
        print('missing  = %s' % (missing[:40],))
    else:
        print('missing  = none')

    # ---- 拼图 ----
    raw = bytearray(b'\x80' * (WIDTH * HEIGHT * 2))
    for r, data in rows.items():
        if r < HEIGHT:
            off = r * LINEB
            n = min(len(data), LINEB)
            raw[off:off + n] = data[:n]

    rawp = args.out + '.raw'
    with open(rawp, 'wb') as f:
        f.write(raw)
    print('wrote %s (%d bytes)' % (rawp, len(raw)))

    #  原始串口流 (调试用)
    streamp = args.out + '.stream'
    with open(streamp, 'wb') as f:
        f.write(bytes(rawstream))
    print('wrote %s (%d bytes)' % (streamp, len(rawstream)))
    if rawstream:
        print('  first 48 bytes: %s' % bytes(rawstream[:48]).hex(' '))

    if not args.no_png and len(rows):
        try:
            from PIL import Image
            import numpy as np
            rgb = yuyv_to_rgb(bytes(raw), WIDTH, HEIGHT)
            pngp = args.out + '.png'
            Image.fromarray(rgb, 'RGB').save(pngp)
            print('wrote %s' % pngp)
        except Exception as e:
            print('PNG failed: %r' % e)

    return 0 if len(rows) == HEIGHT else 2


if __name__ == '__main__':
    sys.exit(main())
