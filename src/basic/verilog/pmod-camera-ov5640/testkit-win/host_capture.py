#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""host_capture.py -- 接收 iCESugar 拍照固件发来的图像行包, 拼成 PNG。

同时支持 OV2640 / OV5640 两种摄像头(协议完全相同: 640x480 YUYV, 分带扫描,
A5 5A | row(2,LE) | len(2,LE) | data[len] | crc(2,LE), CRC16/CCITT-FALSE,
覆盖"包头4字节 + 本行数据", magic 不参与计算)。

用法:
    # 整合目录(两个固件放在一起) —— 用 --sensor 选固件
    python host_capture.py --sensor ov2640 --flash
    python host_capture.py --sensor ov5640 --flash

    # 只收不烧录 / 换波特率 / 收多久
    python host_capture.py --sensor ov2640
    python host_capture.py --sensor ov2640 --baud 115200 --seconds 90

    # 手动指定固件和输出名(文件名里带 ov2640/ov5640 会自动认出传感器)
    python host_capture.py --flash --bin top_photo-ov2640.bin --out my_shot

固件查找顺序(脚本所在目录):
    1) top_photo-<sensor>.bin     整合目录的命名, 两份固件并存不打架
    2) top_photo.bin              单个工程目录的命名(兼容原来的用法)
也可以用环境变量 ICESP_DIR 指定目录, ICESPROG 指定 icesprog.exe。

输出:
    photo-<sensor>.raw    拼好的原始 YUYV (640*480*2 字节, 缺行填 0x80)
    photo-<sensor>.png    转成 RGB 的 PNG
    photo-<sensor>.stream 原始串口流 (调试用)
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

SENSORS = ('ov2640', 'ov5640')
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


def open_serial(port, baud, wait_s):
    """打开串口, 端口被占用时等待并重试。

    坑: 同一个 iCELINK CDC 端口同一时间只能被一个进程打开。
    连着双击两个测试 .bat 时, 后一个会直接抛
        SerialException: could not open port 'COM419': PermissionError(13)
    然后脚本崩在开端口这步, 一个小文件都写不出来, 看起来就是"测试不通过"。
    这里改成先等端口空出来, 再烧录、再抓。
    """
    t0 = time.time()
    warned = False
    while True:
        try:
            return serial.Serial(port, baud, timeout=0.02)
        except Exception as e:
            if time.time() - t0 > wait_s:
                print('!! 端口 %s 打不开: %r' % (port, e), flush=True)
                print('   端口一直被占用, 多半是另一个测试还在跑'
                      '(先关掉那个窗口, 或等它跑完)', flush=True)
                sys.exit(1)
            if not warned:
                print('  端口 %s 被占用, 等待中...(%r)' % (port, e), flush=True)
                warned = True
            time.sleep(1.0)


def sensor_of(path):
    """从固件文件名里认出是哪颗传感器(top_photo-ov2640.bin -> 'ov2640')。"""
    name = os.path.basename(path).lower()
    for s in SENSORS:
        if s in name:
            return s
    return None


def find_bin(sensor):
    """按优先级找拍照固件:
         1) top_photo-<sensor>.bin   整合目录(两份固件并存)
         2) top_photo.bin            单个工程目录(兼容原用法)
       找不到返回 None。
    """
    for name in ('top_photo-%s.bin' % sensor, 'top_photo.bin'):
        p = os.path.join(WS, name)
        if os.path.isfile(p):
            return p
    return None


def wait_port_free(port, wait_s):
    """等串口空出来(只是试开一下就关), 避免打断正在跑的另一个测试。"""
    t0 = time.time()
    warned = False
    while True:
        try:
            s = serial.Serial(port, 115200, timeout=0.02)
            s.close()
            return True
        except Exception as e:
            if time.time() - t0 > wait_s:
                print('!! 端口 %s 一直被占用: %r' % (port, e), flush=True)
                sys.exit(1)
            if not warned:
                print('  端口 %s 被占用(另一个测试还在跑?), 等待中...'
                      % port, flush=True)
                warned = True
            time.sleep(1.0)


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
    ap = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description='iCESugar 拍照固件 -> YUYV -> PNG (OV2640 / OV5640)')
    ap.add_argument('--sensor', choices=SENSORS, default='ov2640',
                    help='用哪颗摄像头对应的固件 (默认 ov2640)')
    ap.add_argument('--flash', action='store_true', help='先烧录拍照固件再收')
    ap.add_argument('--bin', default=None,
                    help='拍照固件路径 (默认在脚本目录找 top_photo-<sensor>.bin / top_photo.bin)')
    ap.add_argument('--baud', type=int, default=115200)
    ap.add_argument('--seconds', type=float, default=120.0)
    ap.add_argument('--port-wait', type=float, default=120.0,
                    help='端口被占用时最多等多久(秒), 默认 120')
    ap.add_argument('--out', default=None,
                    help='输出前缀 (默认 photo-<sensor>)')
    ap.add_argument('--no-png', action='store_true')
    ap.add_argument('--no-stats', action='store_true', help='不打印亮度统计')
    args = ap.parse_args()

    # ---- 选固件 / 定输出名 --------------------------------------------
    sensor = args.sensor
    binp = args.bin
    if binp is None:
        binp = find_bin(sensor)
        if binp is None:
            print('!! 找不到拍照固件: %s 下找过 top_photo-%s.bin 和 top_photo.bin'
                  % (WS, sensor), flush=True)
            print('   用 --bin 直接指定也可以', flush=True)
            sys.exit(1)
    else:
        s = sensor_of(binp)
        if s:
            sensor = s           # 文件名说了算
    out = args.out or os.path.join(WS, 'photo-%s' % sensor)

    print('sensor  = %s' % sensor)
    print('firmware= %s' % binp)
    print('out     = %s{.raw,.png,.stream}' % out)

    # ---- 先找到端口, 并等它空出来(别打断正在跑的另一个测试) ----
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

    if args.flash:
        wait_port_free(port, args.port_wait)
        print('--- flash %s ---' % binp, flush=True)
        r = subprocess.run([ICESPROG, binp], capture_output=True, text=True)
        print((r.stdout or '').strip())
        print('icesprog exit=%d' % r.returncode, flush=True)
        time.sleep(1.5)

    ser = open_serial(port, args.baud, args.port_wait)

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
            print('  %.1fs  bytes=%d  ok=%d  bad=%d  rows=%d/%d'
                  % (time.time() - t0, total, good, badcrc, len(rows), HEIGHT),
                  flush=True)
        if len(rows) >= HEIGHT:
            print('  got all %d rows' % HEIGHT, flush=True)
            break

    ser.close()

    missing = [r for r in range(HEIGHT) if r not in rows]
    print('---- summary ----', flush=True)
    print('sensor   = %s' % sensor)
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

    rawp = out + '.raw'
    with open(rawp, 'wb') as f:
        f.write(raw)
    print('wrote %s (%d bytes)' % (rawp, len(raw)))

    #  原始串口流 (调试用)
    streamp = out + '.stream'
    with open(streamp, 'wb') as f:
        f.write(bytes(rawstream))
    print('wrote %s (%d bytes)' % (streamp, len(rawstream)))
    if rawstream:
        print('  first 48 bytes: %s' % bytes(rawstream[:48]).hex(' '))

    # ---- 亮度统计 (判断曝光/白平衡够不够, 一眼就能看出来) ----
    if not args.no_stats and len(rows):
        try:
            import numpy as np
            a = np.frombuffer(bytes(raw), dtype=np.uint8)
            y = a[0::2].astype(np.float32)
            u = a[1::4].astype(np.float32)
            v = a[3::4].astype(np.float32)
            sat = float((y >= 250).mean() * 100.0)
            print('Y mean=%.1f min=%d max=%d  sat(>=250)=%.1f%%'
                  % (y.mean(), y.min(), y.max(), sat))
            print('U mean=%.1f  V mean=%.1f' % (u.mean(), v.mean()))
            if y.mean() < 24:
                print('>>> 画面几乎全黑: 先确认灯已开、镜头保护膜已撕')
            elif sat > 5.0:
                print('>>> 过曝: 高光死白, 调小 GAIN(0x00) 或 AEC(0x10)')
            elif y.mean() < 60:
                print('>>> 偏暗: 检查 AE 参数块是否写在寄存器表末尾 (见 README 第 5.5 节)')
            else:
                print('>>> 亮度正常')
        except Exception as e:
            print('stats skipped: %r' % e)

    if not args.no_png and len(rows):
        try:
            from PIL import Image
            import numpy as np
            rgb = yuyv_to_rgb(bytes(raw), WIDTH, HEIGHT)
            pngp = out + '.png'
            Image.fromarray(rgb, 'RGB').save(pngp)
            print('wrote %s' % pngp)
        except Exception as e:
            print('PNG failed: %r' % e)

    # ---- 结论 ----
    #  只缺顶部 0/1 两行 = 分带扫描的第一帧还没稳定, 那两行是灰的, 图像仍可用
    if len(rows) == HEIGHT:
        print('VERDICT = OK  (480/480 行全齐)')
        return 0
    if missing and set(missing) <= {0, 1}:
        print('VERDICT = OK  (只缺顶部行 %s, 是首帧没稳的已知现象, 图像仍可用)'
              % (missing,))
        return 0
    print('VERDICT = FAIL  (缺 %d 行: %s)' % (len(missing), missing[:40]))
    return 2


if __name__ == '__main__':
    sys.exit(main())
