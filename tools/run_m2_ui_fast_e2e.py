"""Run real display integration with explicitly simulation-only vendor boundaries."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "sim_work/m2_ui_fast_e2e"


def run(args, name, expect_pass=False):
    p = subprocess.run(args, cwd=OUT, capture_output=True, text=True,
                       errors="replace", timeout=600)
    text = p.stdout + p.stderr
    (OUT / (name + ".log")).write_text(text, encoding="utf-8")
    if p.returncode or re.search(r"\bFAIL\b|\*\* (?:Error|Fatal)", text) or (
            expect_pass and "PASS:" not in text):
        raise RuntimeError(f"{name} failed: {OUT / (name + '.log')}")
    for line in text.splitlines():
        if "PASS:" in line or "CACHE_LATENCY" in line:
            print(line, flush=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if not (OUT / "work").exists():
        run(["vlib", "work"], "vlib")
    run(["vmap", "work", "work"], "vmap")
    rtl = []
    for folder in ("app", "interact", "storage", "framebuf", "dual_board", "display"):
        rtl += sorted((ROOT / "src" / folder).glob("*.v"))
    rtl += [ROOT / "src/top/m2_slave_tf_hdmi_top.v",
            ROOT / "src/top/m2_master_tf_hdmi_top.v",
            ROOT / "sim_tb/loading_overlay/m2_display_vendor_models.v",
            ROOT / "sim_tb/loading_overlay/tb_m2_display_cache_e2e.v",
            ROOT / "sim_tb/loading_overlay/tb_m2_card_error_status.v",
            ROOT / "sim_tb/storage/tb_m2_no_card.v",
            ROOT / "sim_tb/loading_overlay/tb_m2_master_cached_control.v"]
    run(["vlog", "-work", "work", "+incdir+" + str(ROOT / "src/storage"),
         "+incdir+" + str(ROOT / "src/dual_board"), *map(str, rtl)], "compile")
    for test in ("tb_m2_master_cached_control", "tb_m2_card_error_status", "tb_m2_no_card", "tb_m2_display_cache_e2e"):
        run(["vsim", "-c", "work." + test, "-do", "run -all; quit -f"], test, True)


if __name__ == "__main__":
    main()
