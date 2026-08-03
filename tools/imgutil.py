#!/usr/bin/env python3
"""Tiny PNG decode/render helpers for the icon QA tools (no third-party deps).

Used by tools/preview.py and tools/check_icons.py. `render()` needs
rsvg-convert (librsvg) on PATH; `read_png()` is a dependency-free decoder
that handles non-interlaced RGB (type 2), RGBA (type 6) and grayscale
(type 0) PNGs.
"""
import struct
import subprocess
import zlib


def read_png(path):
    data = open(path, 'rb').read()
    pos = 8
    w = h = ct = 0
    idat = b''
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        if typ == b'IHDR':
            w, h, bd, ct = struct.unpack('>IIBB', data[pos + 8:pos + 18])
        elif typ == b'IDAT':
            idat += data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
    raw = zlib.decompress(idat)
    bpp = 4 if ct == 6 else 3 if ct == 2 else 1
    stride = w * bpp

    def paeth(a, b, c):
        p = a + b - c
        pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
        return a if pa <= pb and pa <= pc else (b if pb <= pc else c)

    rows = []
    prev = bytearray(stride)
    off = 0
    for _ in range(h):
        ft = raw[off]
        off += 1
        line = bytearray(raw[off:off + stride])
        off += stride
        if ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xff
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xff
        elif ft == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xff
        elif ft == 4:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                up = prev[i]
                ul = prev[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + paeth(left, up, ul)) & 0xff
        rows.append([tuple(line[i:i + bpp] if bpp > 1 else (line[i], line[i], line[i], 255))
                     for i in range(0, stride, bpp)])
        prev = line
    return w, h, rows


def render(svg_path, png_path, w, h, renderer="rsvg-convert"):
    subprocess.run([renderer, "-w", str(w), "-h", str(h), svg_path, "-o", png_path], check=True)
