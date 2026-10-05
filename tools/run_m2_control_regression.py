"""Run M2 control regressions with Questa; FAIL text counts even if vsim exits 0."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "sim_work" / "m2_control_regression"
TESTS = [
    "app/tb_media_command_controller",
    "app/tb_m1c_coordinator_realmedia",
    "m1abc/tb_m2_open_dispatcher",
    "m1abc/tb_m2_real_media_uart_bridge",
    "m1abc/tb_m2_master_real_control_link",
    "m1abc/tb_m2_master_media_control",
    "storage/tb_m2_real_media_service",
    "storage/tb_m2_media_write_cdc",
    "m1abc/tb_m2_remote_frame_link",
    "m1abc/tb_m2_loading_card",
    "storage/tb_m2_real_media_remote_link",
    "storage/tb_m2_real_media_remote_multiframe",
    "framebuf/tb_line_buffer_pingpong",
    "integration/tb_p1_sdram_hdmi_pipeline",
]


def run(args, name, require_pass=False):
    result = subprocess.run(args, cwd=OUT, capture_output=True, text=True,
                            errors="replace", timeout=180)
    output = result.stdout + result.stderr
    (OUT / (name + ".log")).write_text(output, encoding="utf-8")
    failed = result.returncode or re.search(r"\bFAIL\b|\*\* (?:Error|Fatal)", output)
    if failed or (require_pass and "PASS:" not in output):
        raise RuntimeError(f"{name} failed; see {OUT / (name + '.log')}")
    for line in output.splitlines():
        if "PASS:" in line:
            print(line)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if not (OUT / "work").exists():
        run(["vlib", "work"], "vlib")
    run(["vmap", "work", "work"], "vmap")
    rtl = []
    for directory in ("app", "interact", "storage", "framebuf", "dual_board", "display"):
        rtl.extend(sorted((ROOT / "src" / directory).glob("*.v")))
    rtl.append(ROOT / "src/top/m1abc_master_control_top.v")
    rtl.extend(ROOT / "sim_tb" / (test + ".v") for test in TESTS)
    run(["vlog", "-work", "work", "+incdir+" + str(ROOT / "src/storage"),
         "+incdir+" + str(ROOT / "src/dual_board"), *map(str, rtl)], "compile")
    for test in TESTS:
        name = Path(test).name
        run(["vsim", "-c", "work." + name, "-do", "run -all; quit -f"],
            name, require_pass=True)
    print(f"PASS: all {len(TESTS)} M2 control/display/transport regressions")


if __name__ == "__main__":
    main()
