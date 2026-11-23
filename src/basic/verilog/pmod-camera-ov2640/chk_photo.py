#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""chk_photo.py -- 比对 tb_photo 仿真出来的串口字节流和主机端算法。

用法: python chk_photo.py <sim_photo.hex>
"""
import sys


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


crc16 = crc16_ccitt_false


def hx(b):
    """bytes -> 'aa bb cc' (VM 上的 python3 比较老, bytes.hex(sep) 从 3.8 才有)"""
    return ' '.join('%02x' % x for x in b)


def build_packet(row, data):
    hdr = bytes([row & 0xFF, (row >> 8) & 0xFF, len(data) & 0xFF, (len(data) >> 8) & 0xFF])
    c = crc16(hdr + data)
    return b'\xa5\x5a' + hdr + data + bytes([c & 0xFF, (c >> 8) & 0xFF])


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else 'sim_photo.hex'
    txt = open(path).read().strip().split('\n')
    n = int(txt[0].strip())
    got = bytes.fromhex(txt[1].strip())
    if len(got) != n:
        print('LEN MISMATCH: header says %d, got %d' % (n, len(got)))
        return 1

    stat = bytes(range(0x00, 0x11))[::-1]      # stat_data 低 16 字节, 字节 0 在前
    stat = bytes([0x00, 0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA, 0x99,
                  0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11])

    exp = b''
    exp += build_packet(0xFFFF, stat)
    exp += build_packet(0, bytes(range(1, 9)))
    exp += build_packet(1, bytes(range(9, 17)))

    if got == exp:
        print('PHOTO STREAM OK (%d bytes)' % len(got))
        return 0

    print('PHOTO STREAM MISMATCH')
    print('  expect %d bytes, got %d' % (len(exp), len(got)))
    for i in range(min(len(exp), len(got))):
        if exp[i] != got[i]:
            print('  first diff at byte %d: exp=%02x got=%02x' % (i, exp[i], got[i]))
            print('  exp: %s' % hx(exp[max(0, i - 8):i + 16]))
            print('  got: %s' % hx(got[max(0, i - 8):i + 16]))
            break
    return 1


if __name__ == '__main__':
    sys.exit(main())
