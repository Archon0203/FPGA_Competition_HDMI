"""Exhaustive static + Questa audit for the FPGA_Competition_HDMI project.

Designed for QuestaSim 10.7c / Windows Python.  It does not modify source files,
TD projects, or .git.  Results are written to sim_work/full_project_audit.
"""
from pathlib import Path
import argparse, csv, hashlib, re, shutil, subprocess, sys, time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "sim_work" / "full_project_audit"

# Electrical cross-reference, derived from the board schematic:
# J1 physical pin -> FPGA ball required for the intended B-line signal.
EXPECTED_PINS = {
    "uart_tx":"J13", "uart_rx":"F13",
    "link_data[0]":"D14", "link_data[1]":"G11", "link_data[2]":"G12",
    "link_data[3]":"H13", "link_data[4]":"H14", "link_data[5]":"J14",
    "link_data[6]":"K12", "link_req":"L14", "link_ack":"M14",
    "display_published":"L16",
}
INTENDED_J1 = {
    "link_data[0]":1, "link_data[1]":2, "link_data[2]":3,
    "link_data[3]":5, "link_data[4]":6, "link_data[5]":7,
    "link_data[6]":9, "link_req":10, "link_ack":13, "display_published":32,
    "uart_tx":8, "uart_rx":4,
}

SKIP_DEFAULT = {
    "storage/tb_m2_card_snapshot", "storage/tb_m2_card_spi_snapshot",
    # Protected vendor-core tests are run separately with their own .do files.
    "integration/tb_apug092_external_video_core",
    "framebuf/tb_p1_sdram_cached_adapter_apug011_official",
    "framebuf/tb_sdram_adapter_apug011_official",
}
VENDOR_DO = [
    ("vendor_apug092", ROOT/"sim_tb/integration/run_apug092_external_video_core.do"),
    ("vendor_apug011_cached", ROOT/"sim_tb/framebuf/run_p1_sdram_cached_adapter_apug011_official.do"),
]

ACTIVE_CRITICAL = {
    "app/tb_media_command_controller", "app/tb_m1c_coordinator_realmedia",
    "m1abc/tb_m2_open_dispatcher", "m1abc/tb_m2_real_media_uart_bridge",
    "m1abc/tb_m2_master_real_control_link", "m1abc/tb_m2_master_media_control",
    "storage/tb_m2_real_media_service", "storage/tb_m2_slave_tf_media_core",
    "storage/tb_m2_media_write_cdc", "storage/tb_m2_real_media_remote_link",
    "storage/tb_m2_real_media_remote_multiframe", "storage/tb_m2_bmp_640",
    "m1abc/tb_m2_mailbox_reset_recovery", "m1abc/tb_m2_remote_frame_link",
    "m1abc/tb_m2_remote_frame_idle_resync", "m1abc/tb_m2_hdmi_lock_supervisor",
    "m1abc/tb_m2_loading_card", "framebuf/tb_line_buffer_pingpong",
    "framebuf/tb_line_prefetcher", "framebuf/tb_p1_sdram_cached_adapter",
    "integration/tb_p1_sdram_hdmi_pipeline", "display/tb_hdmi_framebuffer_scanout",
    "full_audit/tb_m2_physical_pin_fault_signature",
}
DEEP_TEST = "full_audit/tb_m2_full_frame_mailbox_640x480"


def parse_adc(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    out = {}
    pat = re.compile(r"set_pin_assignment\s+\{\s*([^}]+?)\s*\}\s+\{[^}]*?LOCATION\s*=\s*([A-Z][0-9]+)", re.I)
    for sig, ball in pat.findall(text):
        out[sig.strip()] = ball.upper()
    return out


def top_of_al(path):
    text=path.read_text(encoding="utf-8",errors="replace")
    m=re.search(r"<TOP_MODULE>.*?<MODULE>([^<]+)</MODULE>.*?</TOP_MODULE>",text,re.S)
    return m.group(1).strip() if m else None


def sha256(path):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(1<<20), b""): h.update(b)
    return h.hexdigest()


def static_audit():
    lines=[]; errors=[]; warns=[]
    def ok(s): lines.append("PASS  "+s)
    def err(s): lines.append("ERROR "+s); errors.append(s)
    def warn(s): lines.append("WARN  "+s); warns.append(s)

    mt=top_of_al(ROOT/"FPGA_Competition_HDMI_MASTER.al")
    st=top_of_al(ROOT/"FPGA_Competition_HDMI_SLAVE.al")
    (ok if mt=="m2_master_tf_hdmi_top" else err)(f"Master TOP={mt}")
    (ok if st=="m2_slave_media_tx_top" else err)(f"Slave TOP={st}")

    ma=parse_adc(ROOT/"constraints/master/master.adc")
    sa=parse_adc(ROOT/"constraints/slave/slave.adc")
    for sig, expected in EXPECTED_PINS.items():
        mb=ma.get(sig); sb=sa.get(sig)
        if mb==expected and sb==expected:
            ok(f"J1-{INTENDED_J1[sig]:02d} {sig}: Master/Slave ball={expected}")
        else:
            err(f"J1-{INTENDED_J1[sig]:02d} {sig}: expected ball {expected}, Master={mb}, Slave={sb}")
    for sig in EXPECTED_PINS:
        if ma.get(sig)!=sa.get(sig): err(f"Master/Slave B-line mismatch {sig}: {ma.get(sig)} vs {sa.get(sig)}")

    # Module inventory + duplicate definitions.
    defs={}
    for p in sorted(ROOT.glob("src/**/*.v")):
        if "vendor/anlogic" in p.as_posix(): continue
        text=p.read_text(errors="replace")
        for name in re.findall(r"(?m)^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)\b",text):
            if name in defs: err(f"duplicate module {name}: {defs[name]} and {p.relative_to(ROOT)}")
            else: defs[name]=p.relative_to(ROOT)
    ok(f"non-vendor RTL inventory: {len(defs)} unique modules")

    # Publication invariant that must make Master 4-LED3 compatible with 8-LED milestones.
    display=(ROOT/"src/top/m2_slave_tf_hdmi_top.v").read_text(errors="replace")
    if re.search(r"assign\s+remote_published\s*=\s*use_framebuffer\s*&&\s*fb_data_seen\s*&&\s*media_succeeded",display,re.S):
        ok("display_published requires use_framebuffer + fb_data_seen + media_succeeded")
    else: warn("could not prove current display_published invariant by static pattern")
    if "remote_diag_byte = {use_framebuffer, fb_data_seen, fb_warm_ready" in display:
        ok("Master 8-LED milestone mapping recognized")
    else: warn("Master diagnostic milestone mapping differs from audit expectation")

    # Stale TD outputs are dangerous: bitstreams must be newer than all sources/constraints/projects.
    inputs=[p for p in ROOT.rglob("*") if p.is_file() and ".git" not in p.parts and p.suffix.lower() in {".v",".vh",".adc",".sdc",".al"}]
    latest=max(inputs,key=lambda p:p.stat().st_mtime)
    bits=list(ROOT.rglob("*.bit"))
    if not bits:
        warn("no .bit files found; fresh TD build is required")
    else:
        newest=max(bits,key=lambda p:p.stat().st_mtime)
        if newest.stat().st_mtime < latest.stat().st_mtime:
            warn(f"STALE BITSTREAM: newest bit {newest.relative_to(ROOT)} is older than {latest.relative_to(ROOT)}; clean rebuild required")
        else: ok(f"bitstream timestamp newer than latest source: {newest.relative_to(ROOT)}")

    # The old bad mapping has a unique fingerprint; detect accidental regression.
    bad={"link_data[3]":"L12","link_data[4]":"J14","link_data[5]":"H13"}
    if any(ma.get(k)==v for k,v in bad.items()):
        err("old FIX5 B-line pin-map regression detected in Master constraints")
    else: ok("old FIX5 data[3:5] pin-map regression absent")

    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/"STATIC_AUDIT.txt").write_text("\n".join(lines)+"\n",encoding="utf-8")
    return errors,warns,lines


def run_cmd(cmd,cwd,timeout,log):
    t0=time.time()
    try:
        r=subprocess.run(cmd,cwd=str(cwd),capture_output=True,text=True,errors="replace",timeout=timeout)
        out=(r.stdout or "")+(r.stderr or "")
        rc=r.returncode
    except subprocess.TimeoutExpired as e:
        out=(e.stdout or "")+(e.stderr or "")+"\nTIMEOUT\n"; rc=124
    log.write_text(out,encoding="utf-8",errors="replace")
    bad=bool(re.search(r"\*\*\s+(?:Error|Fatal)|\bFAIL(?::|\b)",out,re.I))
    return rc,bad,out,time.time()-t0


def discover_tests(card_image=None, deep=True):
    tests=[]
    for p in sorted((ROOT/"sim_tb").rglob("tb_*.v")):
        rel=p.relative_to(ROOT/"sim_tb").with_suffix("").as_posix()
        if rel in SKIP_DEFAULT: continue
        tests.append((rel,p))
    # Our deep test is discovered above; optionally remove it.
    if not deep: tests=[x for x in tests if x[0]!=DEEP_TEST]
    # Card-image tests become runnable when an image is explicitly supplied.
    if card_image:
        for rel in ["storage/tb_m2_card_snapshot","storage/tb_m2_card_spi_snapshot"]:
            tests.append((rel,ROOT/"sim_tb"/(rel+".v")))
    return sorted(tests)


def questa_audit(args):
    qout=OUT/"questa"; qout.mkdir(parents=True,exist_ok=True)
    work=qout/"work"
    if work.exists(): shutil.rmtree(work)
    rows=[]
    for exe in ("vlib","vmap","vlog","vsim"):
        if shutil.which(exe) is None:
            raise RuntimeError(f"{exe} not found in PATH")
    rc,bad,out,sec=run_cmd(["vlib","work"],qout,60,qout/"00_vlib.log")
    if rc or bad: raise RuntimeError("vlib failed")
    run_cmd(["vmap","work","work"],qout,60,qout/"01_vmap.log")

    # Compile every non-protected production RTL source once.  Unknown vendor
    # instances are harmless until a top needing them is elaborated.
    rtl=[]
    for p in sorted((ROOT/"src").rglob("*.v")):
        if "vendor/anlogic" in p.as_posix(): continue
        rtl.append(str(p))
    cmd=["vlog","-work","work","+acc","+incdir+"+str(ROOT/"src/storage"),"+incdir+"+str(ROOT/"src/dual_board"),*rtl]
    rc,bad,out,sec=run_cmd(cmd,qout,300,qout/"02_compile_all_nonvendor_rtl.log")
    if rc or bad:
        raise RuntimeError(f"production RTL compile failed; see {qout/'02_compile_all_nonvendor_rtl.log'}")

    tests=discover_tests(args.card_image,args.deep)
    for index,(rel,p) in enumerate(tests,1):
        safe=rel.replace("/","__")
        clog=qout/(safe+"__compile.log")
        rc,bad,out,csec=run_cmd(["vlog","-work","work","+acc",
            "+incdir+"+str(ROOT/"src/storage"),"+incdir+"+str(ROOT/"src/dual_board"),str(p)],qout,120,clog)
        if rc or bad:
            rows.append([rel,"COMPILE_FAIL",f"{csec:.2f}",str(clog.relative_to(ROOT))]); print(f"COMPILE_FAIL {rel}"); continue
        top=p.stem
        vlog=qout/(safe+"__run.log")
        vcmd=["vsim","-c","-voptargs=+acc","work."+top]
        if args.card_image and rel in {"storage/tb_m2_card_snapshot","storage/tb_m2_card_spi_snapshot"}:
            vcmd.append("+CARD_IMAGE="+str(Path(args.card_image).resolve()))
        vcmd += ["-do","run -all; quit -f"]
        timeout=900 if rel==DEEP_TEST else 240
        rc,bad,out,rsec=run_cmd(vcmd,qout,timeout,vlog)
        pass_text="PASS" in out
        status="PASS" if rc==0 and not bad and (pass_text or "$finish" in out or "End time:" in out) else "FAIL"
        # Tests that use $stop can lack $finish; explicit PASS is sufficient.
        if rc==0 and not bad and pass_text: status="PASS"
        rows.append([rel,status,f"{rsec:.2f}",str(vlog.relative_to(ROOT))])
        print(f"{status:12s} {rel} ({rsec:.1f}s)")

    # Vendor official tests use isolated work libraries and their existing do files.
    if args.vendor:
        # These historical .do files use ../src and ../sim_tb paths, so their
        # intended working directory is ROOT/sim_work (not the .do directory).
        vendor_cwd=ROOT/"sim_work"
        vendor_cwd.mkdir(parents=True,exist_ok=True)
        for name,do in VENDOR_DO:
            log=qout/(name+".log")
            rc,bad,out,rsec=run_cmd(["vsim","-c","-do","do {"+str(do.resolve()).replace('\\','/')+"}"],vendor_cwd,600,log)
            status="PASS" if rc==0 and not bad and "PASS" in out else "FAIL"
            rows.append([name,status,f"{rsec:.2f}",str(log.relative_to(ROOT))])
            print(f"{status:12s} {name} ({rsec:.1f}s)")

    with (OUT/"QUESTA_RESULTS.csv").open("w",newline="",encoding="utf-8-sig") as f:
        w=csv.writer(f); w.writerow(["test","status","seconds","log"]); w.writerows(rows)
    failed=[r for r in rows if r[1]!="PASS"]
    critical_failed=[r for r in failed if r[0] in ACTIVE_CRITICAL or r[0]==DEEP_TEST]
    summary=[f"tests={len(rows)}",f"pass={sum(r[1]=='PASS' for r in rows)}",f"failed={len(failed)}",f"critical_failed={len(critical_failed)}"]
    (OUT/"QUESTA_SUMMARY.txt").write_text("\n".join(summary+["",*["FAIL "+r[0] for r in failed]])+"\n",encoding="utf-8")
    return failed,critical_failed


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--static-only",action="store_true")
    ap.add_argument("--no-deep",dest="deep",action="store_false",help="skip full 640x480 mailbox regression")
    ap.add_argument("--vendor",action="store_true",help="also run protected APUG011/APUG092 official-core tests")
    ap.add_argument("--card-image",help="raw SD-card image for the two snapshot tests")
    args=ap.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    errors,warns,lines=static_audit()
    print("\n".join(lines))
    if errors:
        print(f"\nSTATIC AUDIT FAILED: {len(errors)} error(s). Questa not started.")
        return 2
    if args.static_only:
        print(f"\nPASS: static audit ({len(warns)} warning(s)); see {OUT/'STATIC_AUDIT.txt'}")
        return 0
    failed,critical=questa_audit(args)
    if critical:
        print(f"\nFAIL: {len(critical)} ACTIVE/DEEP regression(s) failed. See {OUT/'QUESTA_RESULTS.csv'}")
        return 3
    if failed:
        print(f"\nPASS active gate, but {len(failed)} legacy/optional test(s) failed; inspect {OUT/'QUESTA_RESULTS.csv'}")
        return 0
    print(f"\nPASS: full project audit completed; see {OUT/'QUESTA_RESULTS.csv'}")
    return 0

if __name__=="__main__":
    sys.exit(main())
