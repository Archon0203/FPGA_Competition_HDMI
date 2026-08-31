#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_sd_card.py —— 生成一个最小 FAT32 SD 卡镜像。

本工具只覆盖 `fat32_scan` 当前可解析的结构：MBR 单 FAT32 分区(0x0C)、
BPB、FAT1/FAT2、根目录簇，以及文件连续数据区。根目录文件使用 8.3 短名；
.vseq 在 FAT32 目录项中按 SEQ 扩展名保存，.bmp 按 BMP 保存。

这不是完整分区工具，只用于 FPGA 侧预置测试媒体；后续若 fat32_scan 扩展
VFAT/子目录，再升级本脚本。
"""

import argparse
import os
import struct
import sys

SECTOR = 512
PART_LBA = 2048
RESERVED = 32
SPC = 1
NUM_FATS = 2
FAT_SIZE = 256
TOTAL_SECTORS = 65536


def pad_name(base, length):
    b = base.upper().replace(" ", "")[:length]
    if not b:
        raise ValueError("短名不能为空")
    return b.ljust(length, " ")


def make_83(base, ext):
    name = pad_name(base, 8)
    extension = pad_name(ext, 3)
    return name.encode("ascii"), extension.encode("ascii")


def put16(buf, off, val):
    struct.pack_into("<H", buf, off, val & 0xFFFF)


def put32(buf, off, val):
    struct.pack_into("<I", buf, off, val & 0xFFFFFFFF)


def build_mbr():
    mbr = bytearray(SECTOR)
    # 分区表从 446 开始，只写一个 FAT32 分区
    off = 446
    mbr[off] = 0x00               # boot flag
    mbr[off + 1] = 0x20
    mbr[off + 2] = 0x21
    mbr[off + 3] = 0x00
    mbr[off + 4] = 0x0C           # FAT32 LBA
    mbr[off + 5] = 0xFE
    mbr[off + 6] = 0xFF
    mbr[off + 7] = 0xFF
    put32(mbr, off + 8, PART_LBA)
    part_sectors = TOTAL_SECTORS - PART_LBA
    put32(mbr, off + 12, part_sectors)
    mbr[510] = 0x55
    mbr[511] = 0xAA
    return mbr


def build_boot():
    boot = bytearray(SECTOR)
    boot[0:3] = b"\xEB\x58\x90"
    boot[3:11] = b"MSWIN4.1"
    put16(boot, 11, SECTOR)
    boot[13] = SPC
    put16(boot, 14, RESERVED)
    boot[16] = NUM_FATS
    put16(boot, 17, 0)            # FAT32 根目录项数固定为 0
    put16(boot, 19, 0)            # 总扇区数小于 65535 时为 0，用 FAT32 字段
    boot[21] = 0xF8
    put16(boot, 22, 0)            # FAT16 扇区数为 0
    put16(boot, 24, 63)
    put16(boot, 26, 255)
    put32(boot, 28, PART_LBA)
    put32(boot, 32, TOTAL_SECTORS)
    put32(boot, 36, FAT_SIZE)
    put16(boot, 40, 0)
    put16(boot, 42, 0)
    put32(boot, 44, 2)            # root cluster
    put16(boot, 48, 1)            # FSInfo sector
    put16(boot, 50, 6)            # backup boot sector
    boot[64] = 0x80
    boot[66] = 0x29
    boot[67:71] = b"\x12\x34\x56\x78"
    boot[71:82] = b"NO NAME    "
    boot[82:90] = b"FAT32   "
    boot[510] = 0x55
    boot[511] = 0xAA
    return boot


def build_fsinfo():
    fs = bytearray(SECTOR)
    put32(fs, 0, 0x41615252)
    put32(fs, 484, 0x61417272)
    put32(fs, 488, 0xFFFFFFFF)
    put32(fs, 492, 3)             # 下一个空闲簇
    fs[508:512] = b"\x00\x00\x55\xAA"
    return fs


def root_sector():
    return PART_LBA + RESERVED + NUM_FATS * FAT_SIZE


def build_dir_entry(base, ext, first_cluster, size):
    name, extension = make_83(base, ext)
    e = bytearray(32)
    e[0:8] = name
    e[8:11] = extension
    e[11] = 0x20
    put16(e, 20, first_cluster >> 16)
    put16(e, 26, first_cluster & 0xFFFF)
    put32(e, 28, size)
    return e


def build_image(entries, total_sectors=TOTAL_SECTORS):
    image = bytearray(total_sectors * SECTOR)
    data_start = root_sector() + SPC

    image[0:SECTOR] = build_mbr()
    image[PART_LBA * SECTOR:(PART_LBA + 1) * SECTOR] = build_boot()
    image[(PART_LBA + 1) * SECTOR:(PART_LBA + 2) * SECTOR] = build_fsinfo()

    fat1 = PART_LBA + RESERVED
    fat2 = fat1 + FAT_SIZE

    # 簇 0/1/2
    put32(image, fat1 * SECTOR + 0, 0x0FFFFFF8)
    put32(image, fat1 * SECTOR + 4, 0x0FFFFFFF)
    put32(image, fat1 * SECTOR + 8, 0x0FFFFFFF)

    root_sec = root_sector()
    root_buf = bytearray()
    next_cluster = 3
    for base, ext, data in entries:
        size = len(data)
        clusters = (size + SPC * SECTOR - 1) // (SPC * SECTOR)
        first_cluster = next_cluster
        root_buf += build_dir_entry(base, ext, first_cluster, size)
        # 写 FAT 链
        for i in range(clusters):
            clu = first_cluster + i
            val = 0x0FFFFFFF if i == clusters - 1 else clu + 1
            put32(image, fat1 * SECTOR + clu * 4, val)
            put32(image, fat2 * SECTOR + clu * 4, val)
        # 写文件数据
        sec = data_start + (first_cluster - 2) * SPC
        image[sec * SECTOR:sec * SECTOR + size] = data
        next_cluster += clusters

    # 根目录写入 cluster 2
    if len(root_buf) < SPC * SECTOR:
        root_buf.extend(b"\x00" * (SPC * SECTOR - len(root_buf)))
    image[root_sec * SECTOR:root_sec * SECTOR + len(root_buf)] = root_buf
    return image


def read_image_entries(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) != TOTAL_SECTORS * SECTOR:
        raise ValueError("镜像长度错误")
    root_sec = root_sector()
    entries = []
    for i in range(16):
        off = root_sec * SECTOR + i * 32
        e = data[off:off + 32]
        if e[0] == 0:
            break
        name = e[0:8].decode("ascii").strip()
        ext = e[8:11].decode("ascii").strip()
        cluster = (struct.unpack_from("<H", e, 20)[0] << 16) | struct.unpack_from("<H", e, 26)[0]
        size = struct.unpack_from("<I", e, 28)[0]
        entries.append((name, ext, cluster, size))
    return entries


def main():
    ap = argparse.ArgumentParser(description="生成最小 FAT32 SD 卡镜像")
    ap.add_argument("--out", required=True, help="输出镜像路径")
    ap.add_argument("--bmp", action="append", default=[], help="BMP 文件，可多次传入")
    ap.add_argument("--vseq", action="append", default=[], help=".vseq 文件，可多次传入")
    ap.add_argument("--verify", action="store_true", help="生成后回读目录项")
    args = ap.parse_args()

    if not args.out.lower().endswith(".img"):
        args.out += ".img"

    entries = []
    for p in args.bmp:
        with open(p, "rb") as f:
            data = f.read()
        base = os.path.splitext(os.path.basename(p))[0]
        entries.append((base, "BMP", data))
    for p in args.vseq:
        with open(p, "rb") as f:
            data = f.read()
        base = os.path.splitext(os.path.basename(p))[0]
        entries.append((base, "SEQ", data))

    if not entries:
        print("错误: 至少提供一个 --bmp 或 --vseq 文件", file=sys.stderr)
        return 1
    if len(entries) > 16:
        print("错误: 当前工具最多支持 16 个根目录项", file=sys.stderr)
        return 1

    image = build_image(entries)
    with open(args.out, "wb") as f:
        f.write(image)

    if args.verify:
        got = read_image_entries(args.out)
        print("OK: %s entries=%d" % (args.out, len(got)))
        for name, ext, cluster, size in got:
            print("  %-8s.%-3s cluster=%d size=%d" % (name, ext, cluster, size))
    else:
        print("OK: %s sectors=%d" % (args.out, TOTAL_SECTORS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
