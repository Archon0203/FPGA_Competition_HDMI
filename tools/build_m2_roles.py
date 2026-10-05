"""Build the two active TD projects in isolation, preserving their GUI _Runs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TD = Path("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116")


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--role", choices=("master", "slave", "both"), default="both")
    parser.add_argument("--td", type=Path, default=DEFAULT_TD)
    parser.add_argument("--output", type=Path, default=ROOT / "sim_work/m2_master_output")
    args = parser.parse_args()
    exe = args.td / "bin/td_commands_prompt.exe"
    flow = args.td / "doc/scripts/DefaultFlow.tcl"
    roles = ("master", "slave") if args.role == "both" else (args.role,)
    for role in roles:
        name = "FPGA_Competition_HDMI_" + role.upper()
        project = ROOT / (name + ".al")
        subprocess.run([sys.executable, str(ROOT / "tools/check_td_project.py"),
                        str(project)], check=True)
        original = project.read_text(encoding="utf-8")
        top = re.search(r"<MODULE>([^<]+)</MODULE>", original)[1]
        adc = ROOT / "constraints" / role / (role + ".adc")
        sdc = ROOT / "constraints" / role / (role + ".sdc")
        sources = {project, adc, sdc}
        sources.update(ROOT / p for p in re.findall(r'<File Path="([^"]+)"', original))
        sources.update((ROOT / "src").rglob("*.vh"))
        hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in sorted(sources) if p.is_file()}
        prj = re.sub(r'(<File Path=")([^"]+)',
                     lambda m: m[1] + (ROOT / m[2]).as_posix(), original)
        for stage in ("syn_1", "phy_1"):
            folder = args.output.resolve() / role / stage
            folder.mkdir(parents=True, exist_ok=True)
            (folder / (name + ".prj")).write_text(prj, encoding="utf-8")
            cfg = (f'set ADCList {{"{adc.as_posix()}"}}\n'
                   f'set SDCList {{"{sdc.as_posix()}"}}\n'
                   'set area_option -packarea\nset device_name eagle_s20.db\n'
                   'set package_name EG4S20BG256\n'
                   f'set prj_name {{{name}}}\nset top_model_name {{{top}}}\n')
            if stage == "syn_1":
                cfg += 'set run_type syn\nset start_step read_design\nset end_step opt_gate\n'
            else:
                cfg += ('set run_type phy\nset parent ../syn_1\nset start_step opt_place\n'
                        'set end_step bitgen\nset drHoldFix on\nset arr_filter false\n')
            (folder / "settings.cfg").write_text(cfg)
            with (folder / "build.log").open("w", encoding="utf-8") as log:
                result = subprocess.run([str(exe), flow.as_posix()], cwd=folder, stdout=log,
                                        stderr=subprocess.STDOUT, timeout=900)
            report = (folder / "build.log").read_text(encoding="utf-8", errors="replace")
            if result.returncode or re.search(r"\bERROR:|couldn't read file|invalid command", report):
                raise RuntimeError(f"TD failed: {folder / 'build.log'}")
            print(f"{role} {stage} completed", flush=True)
        for relative, sha in hashes.items():
            if hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() != sha:
                raise RuntimeError(f"Source changed during build: {relative}")
        phy = args.output.resolve() / role / "phy_1"
        timing = (phy / "final_timing.rpt").read_text(errors="replace")
        setup = re.search(r"SWNS:\s*([-.\d]+)ns, STNS:\s*([-.\d]+)ns", timing)
        hold = re.search(r"HWNS:\s*([-.\d]+)ns, HTNS:\s*([-.\d]+)ns", timing)
        if not setup or not hold or any(float(m[1]) < 0 or float(m[2]) != 0 for m in (setup, hold)):
            raise RuntimeError(f"Timing failed: {phy / 'final_timing.rpt'}")
        bit = phy / (name + ".bit")
        manifest = {"role": role, "top": top, "board_validation": "PENDING",
                    "bit_sha256": hashlib.sha256(bit.read_bytes()).hexdigest(),
                    "source_sha256": hashes,
                    "SWNS_ns": float(setup[1]), "HWNS_ns": float(hold[1])}
        (args.output.resolve() / role / "manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(f"PASS: {role} BitGen, setup={setup[1]} ns hold={hold[1]} ns", flush=True)


if __name__ == "__main__":
    main()

