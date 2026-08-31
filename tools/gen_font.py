#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_font.py —— 生成 OSD 字符点阵 ROM 数据。

输出一个 8x16 点阵 HEX 文件，每行 8bit，共 16 个字符 x 16 行 = 256 行。
行内 bit7 为最左像素，bit0 为最右像素；字符 0..9、A..F 使用内置 5x7
字形，水平左对齐到 8 列、垂直居中到 16 行。

该文件后续可被 `osd_overlay` 的 ROM 初始化逻辑读取，或由人工替换
`src/display/osd_overlay.v` 中的测试字模。
"""

import argparse
import os
import sys

GLYPHS_5X7 = {
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D": ["11100", "10010", "10001", "10001", "10001", "10010", "11100"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
}


def glyph_to_rows(ch):
    g = GLYPHS_5X7[ch]
    rows = []
    for y in range(16):
        if y < 4 or y >= 11:
            rows.append(0x00)
        else:
            row5 = g[y - 4]
            val = 0
            for i, bit in enumerate(row5):
                if bit == "1":
                    val |= 1 << (7 - i)  # bit7 = 最左像素
            rows.append(val)
    return rows


def build_rom():
    chars = "0123456789ABCDEF"
    rom = []
    for ch in chars:
        rom.extend(glyph_to_rows(ch))
    if len(rom) != 256:
        raise ValueError("ROM 行数异常")
    return rom


def write_hex(path, rom):
    with open(path, "w", encoding="ascii", newline="\n") as f:
        for v in rom:
            f.write("%02X\n" % v)


def read_hex(path):
    with open(path, "r", encoding="ascii") as f:
        lines = [ln.strip() for ln in f if ln.strip()]
    if len(lines) != 256:
        raise ValueError("HEX 行数 %d != 256" % len(lines))
    return [int(ln, 16) for ln in lines]


def main():
    ap = argparse.ArgumentParser(description="生成 OSD 8x16 字模 ROM")
    ap.add_argument("--out", required=True, help="输出 .hex 路径")
    ap.add_argument("--verify", action="store_true", help="生成后回读校验")
    args = ap.parse_args()

    if not args.out.lower().endswith(".hex"):
        args.out += ".hex"

    rom = build_rom()
    write_hex(args.out, rom)

    if args.verify:
        got = read_hex(args.out)
        if got != rom:
            print("FAIL: verify mismatch", file=sys.stderr)
            return 1

    print("OK: %s lines=%d" % (args.out, len(rom)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
