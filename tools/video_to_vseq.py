#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
video_to_vseq.py —— 把原始帧序列打包成自定义 .vseq 容器(FPGA 播放用)。

格式(见 docs/06):
    Header(64B, 小端):
      [0:4]  magic "VSEQ"       [4] version
      [5:6]  width(u16)         [7:8] height(u16)
      [9]    bpp                [10]  fps
      [11:12] frame_count(u16)  [13:63] reserved=0
    Body: frame_count * frame_size 字节, 逐帧连续。

默认输出 YUV444(每像素 3B, header.bpp=24)，可直接由
`vseq_yuv_unpack` 分组后喂给 `color_space`。
YUV420 为 planar Y/U/V 布局，保存带宽但需要额外的 planar->交错
去交错器，不能直接与 `yuv420_upsample` 对接。
"""

import argparse
import os
import struct
import sys

MAGIC = b"VSEQ"
VERSION = 1
HEADER_SIZE = 64

OUTPUT_FORMATS = {
    "yuv420": 12,
    "yuv444": 24,
    "rgb565": 16,
    "rgb888": 24,
    "gray8": 8,
}


def clip8(v):
    v = int(v)
    return 0 if v < 0 else (255 if v > 255 else v)


def pack_header(width, height, bpp, fps, frame_count):
    """生成 64 字节小端头。"""
    hdr = bytearray(HEADER_SIZE)
    hdr[0:4] = MAGIC
    hdr[4] = VERSION & 0xFF
    hdr[5:7] = struct.pack("<H", width & 0xFFFF)
    hdr[7:9] = struct.pack("<H", height & 0xFFFF)
    hdr[9] = bpp & 0xFF
    hdr[10] = fps & 0xFF
    hdr[11:13] = struct.pack("<H", frame_count & 0xFFFF)
    return bytes(hdr)


def parse_header(path):
    with open(path, "rb") as f:
        hdr = f.read(HEADER_SIZE)
    if len(hdr) != HEADER_SIZE:
        raise ValueError("header 长度不足 64B")
    if hdr[0:4] != MAGIC:
        raise ValueError("magic 不是 VSEQ")
    width = struct.unpack("<H", hdr[5:7])[0]
    height = struct.unpack("<H", hdr[7:9])[0]
    bpp = hdr[9]
    fps = hdr[10]
    frame_count = struct.unpack("<H", hdr[11:13])[0]
    return width, height, bpp, fps, frame_count


def validate_vseq(path, width, height, bpp, fps, frame_count):
    """回读并校验 header 与 body 总长度。"""
    got = parse_header(path)
    if got != (width, height, bpp, fps, frame_count):
        raise ValueError("header 字段不一致: got=%s exp=%s" %
                         (got, (width, height, bpp, fps, frame_count)))
    frame_size = width * height * bpp // 8
    expected = HEADER_SIZE + frame_size * frame_count
    actual = os.path.getsize(path)
    if actual != expected:
        raise ValueError("文件长度 %d != 期望 %d" % (actual, expected))


def synth_rgb888(width, height, frame_idx):
    """生成一帧 RGB888 测试图案(无第三方依赖)。"""
    out = bytearray(width * height * 3)
    for y in range(height):
        for x in range(width):
            r = (x + frame_idx * 3) & 0xFF
            g = (y + frame_idx * 5) & 0xFF
            b = (x + y + frame_idx * 7) & 0xFF
            i = (y * width + x) * 3
            out[i] = r
            out[i + 1] = g
            out[i + 2] = b
    return bytes(out)


def rgb_to_y(r, g, b):
    return clip8(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16)


def rgb_to_cb(r, g, b):
    return clip8(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128)


def rgb_to_cr(r, g, b):
    return clip8(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128)


def rgb888_to_yuv420(rgb, width, height):
    """RGB888 -> BT.601 limited-range YUV420(planar Y, U, V)。"""
    if width % 2 or height % 2:
        raise ValueError("YUV420 要求宽高均为偶数")
    y_plane = bytearray(width * height)
    u_plane = bytearray((width // 2) * (height // 2))
    v_plane = bytearray((width // 2) * (height // 2))
    for by in range(0, height, 2):
        for bx in range(0, width, 2):
            r_sum = g_sum = b_sum = 0
            for dy in (0, 1):
                for dx in (0, 1):
                    x = bx + dx
                    y = by + dy
                    i = (y * width + x) * 3
                    r = rgb[i]
                    g = rgb[i + 1]
                    b = rgb[i + 2]
                    r_sum += r
                    g_sum += g
                    b_sum += b
                    y_plane[y * width + x] = rgb_to_y(r, g, b)
            cb = rgb_to_cb(r_sum // 4, g_sum // 4, b_sum // 4)
            cr = rgb_to_cr(r_sum // 4, g_sum // 4, b_sum // 4)
            u_plane[(by // 2) * (width // 2) + (bx // 2)] = cb
            v_plane[(by // 2) * (width // 2) + (bx // 2)] = cr
    return bytes(y_plane) + bytes(u_plane) + bytes(v_plane)


def rgb888_to_yuv444(rgb, width, height):
    """RGB888 -> BT.601 limited-range YUV444，逐像素 Y,Cb,Cr 交错。"""
    out = bytearray(width * height * 3)
    for i in range(width * height):
        r = rgb[i * 3]
        g = rgb[i * 3 + 1]
        b = rgb[i * 3 + 2]
        out[i * 3] = rgb_to_y(r, g, b)
        out[i * 3 + 1] = rgb_to_cb(r, g, b)
        out[i * 3 + 2] = rgb_to_cr(r, g, b)
    return bytes(out)


def rgb888_to_rgb565(rgb, width, height):
    out = bytearray(width * height * 2)
    for i in range(width * height):
        r = rgb[i * 3]
        g = rgb[i * 3 + 1]
        b = rgb[i * 3 + 2]
        pix = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
        out[i * 2] = pix & 0xFF
        out[i * 2 + 1] = (pix >> 8) & 0xFF
    return bytes(out)


def rgb888_to_gray8(rgb, width, height):
    out = bytearray(width * height)
    for i in range(width * height):
        r = rgb[i * 3]
        g = rgb[i * 3 + 1]
        b = rgb[i * 3 + 2]
        out[i] = (r * 299 + g * 587 + b * 114) // 1000
    return bytes(out)


def raw_to_rgb888(raw, width, height, input_bpp):
    if input_bpp == 24:
        return bytes(raw)
    out = bytearray(width * height * 3)
    for i in range(width * height):
        if input_bpp == 16:
            pix = raw[i * 2] | (raw[i * 2 + 1] << 8)
            r5 = (pix >> 11) & 0x1F
            g6 = (pix >> 5) & 0x3F
            b5 = pix & 0x1F
            r = (r5 << 3) | (r5 >> 2)
            g = (g6 << 2) | (g6 >> 4)
            b = (b5 << 3) | (b5 >> 2)
        elif input_bpp == 8:
            g = r = b = raw[i]
        else:
            raise ValueError("raw 输入仅支持 8/16/24 bpp")
        out[i * 3] = r
        out[i * 3 + 1] = g
        out[i * 3 + 2] = b
    return bytes(out)


def convert_rgb888(rgb, width, height, out_format):
    if out_format == "yuv420":
        return rgb888_to_yuv420(rgb, width, height)
    if out_format == "yuv444":
        return rgb888_to_yuv444(rgb, width, height)
    if out_format == "rgb565":
        return rgb888_to_rgb565(rgb, width, height)
    if out_format == "gray8":
        return rgb888_to_gray8(rgb, width, height)
    return rgb


def read_raw_frames(folder, width, height, input_bpp, frames):
    frame_size = width * height * input_bpp // 8
    out = []
    for i in range(frames):
        p = os.path.join(folder, "frame_%03d.raw" % i)
        with open(p, "rb") as f:
            raw = f.read(frame_size)
        if len(raw) != frame_size:
            raise ValueError("%s 长度 %d != 期望 %d" % (p, len(raw), frame_size))
        out.append(raw)
    return out


def main():
    ap = argparse.ArgumentParser(description="打包 .vseq 容器")
    ap.add_argument("--width", type=int, default=320)
    ap.add_argument("--height", type=int, default=240)
    ap.add_argument("--format", choices=sorted(OUTPUT_FORMATS), default="yuv444",
                    help="输出像素格式，默认 yuv444")
    ap.add_argument("--bpp", type=int, choices=[8, 12, 16, 24], default=None,
                    help="可选：输出 bpp；通常由 --format 自动决定")
    ap.add_argument("--input-bpp", type=int, choices=[8, 16, 24], default=24,
                    help="--dir 原始帧的输入 bpp")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--frames", type=int, default=4)
    ap.add_argument("--gen-test", action="store_true", help="用合成测试图案生成")
    ap.add_argument("--dir", default=None, help="原始帧目录(frame_%03d.raw)")
    ap.add_argument("--out", required=True, help="输出 .vseq 路径")
    ap.add_argument("--validate-only", action="store_true", help="只校验已有文件")
    args = ap.parse_args()

    if args.out.count(".") == 0 or not args.out.lower().endswith(".vseq"):
        args.out += ".vseq"

    out_bpp = OUTPUT_FORMATS[args.format]
    if args.bpp is not None and args.bpp != out_bpp:
        ap.error("--bpp=%d 与 --format=%s 自动 bpp=%d 不一致" %
                 (args.bpp, args.format, out_bpp))

    if args.validate_only:
        validate_vseq(args.out, args.width, args.height, out_bpp,
                      args.fps, args.frames)
        print("OK: validate %s" % args.out)
        return 0

    if args.format == "yuv420" and (args.width % 2 or args.height % 2):
        ap.error("YUV420 输出要求 --width 和 --height 均为偶数")

    if args.gen_test:
        frames = [convert_rgb888(synth_rgb888(args.width, args.height, i),
                                 args.width, args.height, args.format)
                  for i in range(args.frames)]
    elif args.dir:
        raw_frames = read_raw_frames(args.dir, args.width, args.height,
                                     args.input_bpp, args.frames)
        frames = [convert_rgb888(raw_to_rgb888(raw, args.width, args.height, args.input_bpp),
                                 args.width, args.height, args.format)
                  for raw in raw_frames]
    else:
        print("错误: 请用 --gen-test 或 --dir 提供帧来源", file=sys.stderr)
        return 1

    header = pack_header(args.width, args.height, out_bpp, args.fps, len(frames))
    with open(args.out, "wb") as f:
        f.write(header)
        for fr in frames:
            f.write(fr)

    validate_vseq(args.out, args.width, args.height, out_bpp,
                  args.fps, len(frames))
    frame_size = args.width * args.height * out_bpp // 8
    print("OK: %s format=%s width=%d height=%d bpp=%d fps=%d frames=%d size=%d+%d"
          % (args.out, args.format, args.width, args.height, out_bpp, args.fps,
             len(frames), HEADER_SIZE, frame_size * len(frames)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
