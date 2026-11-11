#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Decode an Android boot image header (v0-v2) without any external tools.
Usage: bootimg-info.py <boot.img>
"""
import struct
import sys

d = open(sys.argv[1], 'rb').read()
assert d[:8] == b'ANDROID!', 'not an Android boot image'
(ksz, kaddr, rsz, raddr, ssz, saddr, tags, page, hver, osv) = struct.unpack_from('<10I', d, 8)
name = d[48:64].rstrip(b'\0').decode()
cmd = d[64:64 + 512].rstrip(b'\0').decode()
extra = d[64 + 512 + 32:64 + 512 + 32 + 1024].rstrip(b'\0').decode()
print(f'header_version {hver}  page_size {page}')
print(f'kernel  size {ksz:>10}  addr {kaddr:#010x}')
print(f'ramdisk size {rsz:>10}  addr {raddr:#010x}')
print(f'second  size {ssz:>10}  addr {saddr:#010x}')
print(f'tags addr {tags:#010x}')
# os_version: bits 31..11 = A.B.C (7 bits each), bits 10..0 = year-2000 (7) / month (4)
a, b, c = (osv >> 25) & 0x7f, (osv >> 18) & 0x7f, (osv >> 11) & 0x7f
y, m = ((osv >> 4) & 0x7f) + 2000, osv & 0xf
print(f'os_version {a}.{b}.{c}  os_patch_level {y}-{m:02d}')
if hver >= 1:
    off = 64 + 512 + 32 + 1024
    rdo_size, rdo_off, hdr_size = struct.unpack_from('<IQI', d, off)
    print(f'recovery_dtbo size {rdo_size}  header_size {hdr_size}')
    if hver >= 2:
        dtb_size, dtb_addr = struct.unpack_from('<IQ', d, off + 16)
        print(f'dtb     size {dtb_size:>10}  addr {dtb_addr:#010x}')
        # locate the dtb section and check its magic
        pages = lambda n: (n + page - 1) // page
        dtb_off = page * (1 + pages(ksz) + pages(rsz) + pages(ssz) + pages(rdo_size))
        print(f'dtb magic ok: {d[dtb_off:dtb_off+4] == bytes.fromhex("d00dfeed")}')
    # kernel: gzip? appended dtb?
    k = d[page:page + ksz]
    print(f'kernel starts with gzip magic: {k[:2] == bytes.fromhex("1f8b")};  '
          f'appended dtb present: {bytes.fromhex("d00dfeed") in k[-200000:]}')
print(f'cmdline: {cmd}{extra}')
