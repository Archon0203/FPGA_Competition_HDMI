#!/usr/bin/env python3
r"""Comprehensive QuestaSim regression for M2 A/B loading overlay + bottom subtitle + top-left image-info box.

Covers:
  * loading overlay transparency
  * committed-caption metadata timing
  * 640x480 bottom subtitle raster/font/8.3 formatting
  * top-left rounded translucent RES/RGB box geometry, alpha blend, compact multiplication-sign resolution text and lower-case bit rendering
  * committed width/height/BPP metadata timing
  * FAT32 short-name extraction and catalog propagation
  * Slave->Master filename + resolution/BPP metadata transport, legacy compatibility and CRC rejection
  * A/B framebuffer safe switching and cached SDRAM chain
  * supporting FIFO/CDC/prefetch/scanout regressions in --suite extended

Windows examples:
  py tools\run_m2_loading_info_regression.py --suite core
  py tools\run_m2_loading_info_regression.py --suite extended
  py tools\run_m2_loading_info_regression.py --suite extended --questa-bin D:\Questasim64_10.7c\win64
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "sim_work" / "m2_loading_info_regression"

RTL = [
    "src/display/m2_loading_card.v",
    "src/display/m2_image_subtitle.v",
    "src/display/m2_image_info_overlay.v",
    "src/display/m2_caption_commit.v",
    "src/dual_board/m2_remote_frame.v",
    "src/dual_board/m2_gpio_mailbox.v",
    "src/dual_board/m2_cache_command_cdc.v",
    "src/dual_board/m2_cache_command_router.v",
    "src/storage/fat32_scan.v",
    "src/storage/m1a_catalog_table.v",
    "src/storage/m1a_fat32_catalog.v",
    "src/framebuf/async_fifo.v",
    "src/framebuf/p1_sdram_read_cdc_bridge.v",
    "src/framebuf/line_prefetcher.v",
    "src/framebuf/line_buffer_pingpong.v",
    "src/display/hdmi_framebuffer_scanout.v",
    "src/framebuf/p1_sdram_hdmi_pipeline.v",
    "src/display/hdmi_official_baseline_source.v",
    "src/framebuf/sdram_arbiter.v",
    "src/framebuf/p1_sdram_cached_adapter.v",
    "src/framebuf/m2_media_write_cdc.v",
]

HELPERS = ["sim_tb/framebuf/mock_apug011_app_port.v"]

@dataclass(frozen=True)
class Test:
    source: str
    top: str
    args: tuple[str, ...] = ()
    timeout: int = 300
    label: str | None = None

CORE_TESTS = [
    Test("sim_tb/m1abc/tb_m2_loading_card.v", "tb_m2_loading_card", ("-gERROR_PAGE=1",), label="tb_m2_missing_card_page"),
    Test("sim_tb/loading_overlay/tb_m2_cache_command_cdc.v", "tb_m2_cache_command_cdc"),
    Test("sim_tb/loading_overlay/tb_m2_cache_command_router.v", "tb_m2_cache_command_router"),
    Test("sim_tb/loading_overlay/tb_m2_caption_cache.v", "tb_m2_caption_cache"),
    Test("sim_tb/loading_overlay/tb_m2_remote_frame_filename.v", "tb_m2_remote_frame_filename",
         ("-gCOMPACT=1",), label="tb_m2_remote_compact"),
    Test("sim_tb/loading_overlay/tb_m2_remote_frame_filename.v", "tb_m2_remote_frame_filename",
         ("-gCOMPACT=1", "-gBOTTOM_UP=1"), label="tb_m2_remote_compact_bottomup"),
    Test("sim_tb/m1abc/tb_m2_loading_card.v", "tb_m2_loading_card"),
    Test("sim_tb/loading_overlay/tb_m2_image_subtitle.v", "tb_m2_image_subtitle", timeout=900),
    Test("sim_tb/loading_overlay/tb_m2_image_info_overlay.v", "tb_m2_image_info_overlay", timeout=900),
    Test("sim_tb/loading_overlay/tb_m2_caption_commit.v", "tb_m2_caption_commit"),
    Test("sim_tb/loading_overlay/tb_m2_remote_frame_filename.v", "tb_m2_remote_frame_filename"),
    Test("sim_tb/storage/tb_fat32_scan.v", "tb_fat32_scan", label="tb_fat32_scan_mbr"),
    Test("sim_tb/storage/tb_fat32_scan.v", "tb_fat32_scan", ("-gSUPERFLOPPY=1",), label="tb_fat32_scan_superfloppy"),
    Test("sim_tb/storage/tb_m1a_fat32_catalog.v", "tb_m1a_fat32_catalog"),
    Test("sim_tb/integration/tb_p1_sdram_hdmi_pipeline.v", "tb_p1_sdram_hdmi_pipeline"),
    Test("sim_tb/integration/tb_p1_sdram_hdmi_cached_chain.v", "tb_p1_sdram_hdmi_cached_chain"),
    Test("sim_tb/loading_overlay/tb_m2_loading_overlay_double_buffer_e2e.v", "tb_m2_loading_overlay_double_buffer_e2e", timeout=900),
]

EXTENDED_EXTRA_TESTS = [
    Test("sim_tb/storage/tb_m1a_catalog_table.v", "tb_m1a_catalog_table"),
    Test("sim_tb/m1abc/tb_m2_remote_frame_link.v", "tb_m2_remote_frame_link"),
    Test("sim_tb/m1abc/tb_m2_remote_frame_idle_resync.v", "tb_m2_remote_frame_idle_resync"),
    Test("sim_tb/framebuf/tb_async_fifo.v", "tb_async_fifo"),
    Test("sim_tb/framebuf/tb_p1_sdram_read_cdc_bridge.v", "tb_p1_sdram_read_cdc_bridge"),
    Test("sim_tb/framebuf/tb_line_prefetcher.v", "tb_line_prefetcher"),
    Test("sim_tb/framebuf/tb_line_buffer_pingpong.v", "tb_line_buffer_pingpong"),
    Test("sim_tb/display/tb_hdmi_framebuffer_scanout.v", "tb_hdmi_framebuffer_scanout"),
    Test("sim_tb/framebuf/tb_sdram_arbiter.v", "tb_sdram_arbiter"),
    Test("sim_tb/framebuf/tb_p1_sdram_cached_adapter.v", "tb_p1_sdram_cached_adapter"),
    Test("sim_tb/storage/tb_m2_media_write_cdc.v", "tb_m2_media_write_cdc"),
]

FAIL_RE = re.compile(r"(?:\*\*\s+(?:Error|Fatal))|(?:\bFAIL\s*:)|(?:\bFATAL\s*:)|(?:\bERROR\s*:)", re.I)
PASS_RE = re.compile(r"\bPASS\s*:", re.I)


def prepend_questa_path(questa_bin: str | None) -> None:
    if questa_bin:
        q = str(Path(questa_bin).expanduser().resolve())
        os.environ["PATH"] = q + os.pathsep + os.environ.get("PATH", "")


def require_tools() -> None:
    missing = [x for x in ("vlib", "vmap", "vlog", "vsim") if shutil.which(x) is None]
    if missing:
        raise RuntimeError(
            "Questa executables not found: " + ", ".join(missing) +
            ". Open a Questa command prompt or pass --questa-bin."
        )


def run_cmd(cmd: list[str], cwd: Path, log: Path, timeout: int) -> tuple[int, str, float]:
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=str(cwd), stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True, errors="replace",
                           timeout=timeout)
        text = p.stdout or ""
        rc = p.returncode
    except subprocess.TimeoutExpired as e:
        text = (e.stdout or "") + "\nTIMEOUT\n"
        rc = 124
    log.write_text(text, encoding="utf-8", errors="replace")
    return rc, text, time.time() - t0


def static_contract_check() -> list[str]:
    errors: list[str] = []
    def read(p: str) -> str:
        return (ROOT / p).read_text(encoding="utf-8", errors="replace")

    top = read("src/top/m2_slave_tf_hdmi_top.v")
    subtitle = read("src/display/m2_image_subtitle.v")
    info = read("src/display/m2_image_info_overlay.v")
    commit = read("src/display/m2_caption_commit.v")
    remote = read("src/dual_board/m2_remote_frame.v")
    scan = read("src/storage/fat32_scan.v")
    cat = read("src/storage/m1a_catalog_table.v")
    fatcat = read("src/storage/m1a_fat32_catalog.v")
    slave = read("src/top/m2_slave_media_tx_top.v")
    pipe = read("src/framebuf/p1_sdram_hdmi_pipeline.v")

    checks = [
        ("A/B framebuffer remains 307200 words per bank", "FRAME_BUFFER_WORDS = 21'd307200" in top),
        ("reload writes load_bank while front stays visible", "media_wr_addr_banked" in top and "bank_base(load_bank)" in top),
        ("loading is startup-only; reload keeps old picture", ".overlay_only(1\'b0)" in top and "use_framebuffer && front_valid ? framebuffer_axis_data : loading_rgb" in top),
        ("subtitle is after loading composition", "axis_data_pre_subtitle" in top and "u_image_subtitle" in top),
        ("top-left info overlay is composed after subtitle", "axis_data_with_subtitle" in top and "u_image_info_overlay" in top),
        ("info box is rounded/translucent and bounded top-left", "BOX_X = 10'd12" in info and "BOX_Y = 10'd12" in info and "rounded_hit" in info and "BOX_R = 10'd6" in info and "r_dim" in info and "on_border" in info),
        ("resolution uses compact multiplication sign and unit uses lower-case bit", "CH_MUL = 8'hD7" in info and 'line2_char="b"' in info and 'line2_char="i"' in info and 'line2_char="t"' in info),
        ("caption commit uses framebuffer switch boundary", "framebuffer_switch_pulse" in top and "caption_commit_pulse" in top),
        ("caption pending metadata cannot publish early", "pending_filename_83" in commit and "if (commit_pulse)" in commit),
        ("resolution/BPP metadata shares the same commit", all(x in commit for x in ["pending_image_width", "pending_image_height", "pending_image_bpp", "displayed_image_width"])),
        ("subtitle format contains 8.3 filename path", "filename_83" in subtitle and "base_len" in subtitle),
        ("FAT scanner captures raw 8.3 filename", "file_name_83" in scan and "entry_name_83" in scan),
        ("catalog stores filename per image", "name_mem" in cat and "descriptor_name_83" in cat),
        ("catalog wrapper propagates filename", "descriptor_name_83" in fatcat),
        ("remote protocol carries NAME metadata", "NAME_MARKER" in remote and "filename_valid" in remote),
        ("remote protocol carries CRC-covered INFO metadata", "INFO_MARKER" in remote and "info_valid" in remote and "image_width" in remote and "image_bpp" in remote),
        ("remote filename metadata is CRC-covered", remote.count("crc_word(crc,out_data)") >= 6),
        ("Slave TX connects descriptor filename", "media_descriptor_filename_83" in slave and ".filename_83(media_descriptor_filename_83)" in slave),
        ("Slave TX connects resolution/BPP metadata", all(x in slave for x in ["media_descriptor_width", "media_descriptor_height", ".info_valid(media_descriptor_valid)", ".image_bpp(6'd24)"])),
        ("pipeline still switches on safe frame boundary", "frame_switch_armed && frame_boundary" in pipe),
    ]
    print("STATIC CONTRACT CHECK")
    for name, ok in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
        if not ok:
            errors.append(name)
    return errors


def prepare_work(out: Path) -> None:
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)
    rc, txt, _ = run_cmd(["vlib", "work"], out, out / "00_vlib.log", 60)
    if rc != 0 or FAIL_RE.search(txt):
        raise RuntimeError("vlib failed")
    rc, txt, _ = run_cmd(["vmap", "work", "work"], out, out / "01_vmap.log", 60)
    if rc != 0 or FAIL_RE.search(txt):
        raise RuntimeError("vmap failed")


def compile_file(path: Path, out: Path, seq: int) -> None:
    incs = [
        "+incdir+" + str(ROOT / "src" / "storage"),
        "+incdir+" + str(ROOT / "src" / "dual_board"),
        "+incdir+" + str(ROOT / "src" / "display"),
    ]
    log = out / f"compile_{seq:03d}_{path.stem}.log"
    rc, txt, sec = run_cmd(["vlog", "-work", "work", *incs, str(path)], out, log, 180)
    if rc != 0 or FAIL_RE.search(txt):
        raise RuntimeError(f"compile failed: {path.relative_to(ROOT)} (see {log})")
    print(f"COMPILE PASS  {path.relative_to(ROOT)}  ({sec:.2f}s)")


def run_test(t: Test, out: Path, default_timeout: int, ordinal: int) -> tuple[str, str, float, Path]:
    label = t.label or t.top
    log = out / f"run_{ordinal:02d}_{label}.log"
    cmd = ["vsim", "-c", "-voptargs=+acc", *t.args, f"work.{t.top}", "-do", "run -all; quit -f"]
    timeout = max(default_timeout, t.timeout)
    rc, txt, sec = run_cmd(cmd, out, log, timeout)
    if rc == 124:
        return "TIMEOUT", "process timeout", sec, log
    if rc != 0:
        return "FAIL", f"vsim rc={rc}", sec, log
    if FAIL_RE.search(txt):
        return "FAIL", "ERROR/FAIL/FATAL marker", sec, log
    if not PASS_RE.search(txt):
        return "FAIL", "missing PASS marker", sec, log
    return "PASS", "PASS marker", sec, log


def main() -> int:
    ap = argparse.ArgumentParser(description="M2 loading-overlay + subtitle + image-info Questa regression")
    ap.add_argument("--suite", choices=("core", "extended"), default="extended")
    ap.add_argument("--questa-bin", help="directory containing vlib/vmap/vlog/vsim")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--no-static", action="store_true")
    ap.add_argument("--test-timeout", type=int, default=300)
    args = ap.parse_args()

    if not args.no_static:
        errs = static_contract_check()
        if errs:
            print(f"\nFAIL: {len(errs)} static contract check(s) failed")
            return 2

    prepend_questa_path(args.questa_bin)
    try:
        require_tools()
    except RuntimeError as e:
        print("ERROR:", e)
        return 2

    out = args.out.expanduser().resolve()
    prepare_work(out)
    tests = list(CORE_TESTS)
    if args.suite == "extended":
        tests += EXTENDED_EXTRA_TESTS

    # Compile each unique TB source only once.
    compile_paths = [ROOT / p for p in RTL + HELPERS]
    seen: set[Path] = set(compile_paths)
    for t in tests:
        p = ROOT / t.source
        if p not in seen:
            compile_paths.append(p); seen.add(p)

    try:
        for i, p in enumerate(compile_paths, 1):
            compile_file(p, out, i)
    except RuntimeError as e:
        print("\nFAIL:", e)
        return 3

    rows: list[list[str]] = []
    failures = 0
    print("\nSIMULATION REGRESSION")
    for i, t in enumerate(tests, 1):
        label = t.label or t.top
        status, reason, sec, log = run_test(t, out, args.test_timeout, i)
        if status != "PASS": failures += 1
        rows.append([label, t.top, " ".join(t.args), status, reason, f"{sec:.2f}", str(log)])
        print(f"  {status:7s} {label:48s} {sec:7.2f}s  {reason}")

    csv_path = out / "RESULTS.csv"
    with csv_path.open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f); w.writerow(["test","top","vsim_args","status","reason","seconds","log"]); w.writerows(rows)
    passed = sum(r[3] == "PASS" for r in rows)
    summary = [f"suite={args.suite}", f"tests={len(rows)}", f"pass={passed}", f"fail={failures}", f"results={csv_path}"]
    (out / "SUMMARY.txt").write_text("\n".join(summary)+"\n", encoding="utf-8")
    print("\n" + "\n".join(summary))
    if failures:
        print("FAIL: inspect the per-test logs above")
        return 4
    print("PASS: all selected loading/subtitle/info regressions passed")
    return 0

if __name__ == "__main__":
    sys.exit(main())
