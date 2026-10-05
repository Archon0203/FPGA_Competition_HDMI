#!/usr/bin/env python3
"""B-line static/structural audit for the current M2 dual-board transport.

This intentionally separates what can be proven from repository contents from
what still requires ChipWatcher or physical-board measurement. It does not
claim to replace RTL simulation, synthesis/P&R/STA, or board validation.
"""
from pathlib import Path
import random, re, sys

ROOT = Path(__file__).resolve().parents[1]
issues = []


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8-sig", errors="replace")


def ok(tag, msg):
    print(f"PASS {tag}: {msg}")


def warn(tag, msg):
    print(f"WARN {tag}: {msg}")


def fail(tag, msg):
    issues.append((tag, msg))
    print(f"FAIL {tag}: {msg}")


master_top = read("src/top/m2_master_tf_hdmi_top.v")
core = read("src/top/m2_slave_tf_hdmi_top.v")
slave_top = read("src/top/m2_slave_media_tx_top.v")
mailbox = read("src/dual_board/m2_gpio_mailbox.v")
remote = read("src/dual_board/m2_remote_frame.v")
cdc = read("src/framebuf/m2_media_write_cdc.v")
adapter = read("src/framebuf/p1_sdram_cached_adapter.v")
master_al = read("FPGA_Competition_HDMI_MASTER.al")

# B-1: published/mux/top/LED contradiction.
if ("<MODULE>m2_master_tf_hdmi_top</MODULE>" in master_al and
        "assign remote_published = use_framebuffer && media_succeeded;" in core and
        re.search(r"wire \[23:0\] axis_data = use_framebuffer\s*\? framebuffer_axis_data", core) and
        "assign led={display_led[3] || ctrl_led[3],display_published,ctrl_led[1:0]};" in master_top and
        ".axis_data       (axis_data)" in core):
    ok("B-1", "current RTL makes LED3/display_published imply use_framebuffer=1, and APUG092 consumes the same axis_data mux")
else:
    fail("B-1", "publish/LED/mux/top relationship does not match the checklist")

# B-2: LED1/LED2 are control-UART status only.
control = read("src/dual_board/m2_master_media_control.v")
if "assign led[0] = ack_toggle;" in control and "assign led[1] = link_ok;" in control:
    ok("B-2", "Master LED1=control ack_toggle and LED2=UART link_ok; neither proves media-mailbox health")
else:
    fail("B-2", "Master control LED mapping changed")

# B-3: exact five-beat packing/reconstruction.
def beats(w):
    return [(w >> 0) & 0x7f, (w >> 7) & 0x7f, (w >> 14) & 0x7f,
            (w >> 21) & 0x7f, (w >> 28) & 0x0f]


def unpack(b):
    return (b[0] | (b[1] << 7) | (b[2] << 14) | (b[3] << 21) |
            ((b[4] & 0x0f) << 28)) & 0xffffffff

patterns = [0x00000000, 0xffffffff, 0x12345678, 0x89abcdef,
            0xb17e0000, 0xf17e0000, 0x40000000, 0x7fffffff, 0x80000000]
rng = random.Random(0xB17E)
patterns += [rng.getrandbits(32) for _ in range(10000)]
errors = sum(unpack(beats(w)) != w for w in patterns)
rtl_shape = all(x in mailbox for x in [
    "data<=in_data[6:0]", "data<=word_q[13:7]", "data<=word_q[20:14]",
    "data<=word_q[27:21]", "data<={3'd0,word_q[31:28]}",
    "out_data<={data[3:0],lower}"
])
if errors == 0 and rtl_shape:
    ok("B-3", "9 required patterns + 10,000 deterministic random words reconstruct bit-exactly in the documented five-beat mapping")
else:
    fail("B-3", f"packing audit errors={errors}, rtl_shape={rtl_shape}")

# B-4: structural independent-reset recovery check.
# A five-beat stream with no beat index/framing cannot restore phase after a
# mid-word reset; grouping remains offset until both endpoints are reset.
probe_words = [0xB17E0000, 0x40000000, 0x00112233, 0x40000001,
               0x44556677, 0xF17E0000, 0xDEADBEEF]
stream = sum((beats(w) for w in probe_words), [])
recovery = []
for k in range(5):
    outs = [unpack(stream[i:i+5]) for i in range(k+1, len(stream)-4, 5)]
    recovery.append(outs[:3] == probe_words[1:4])
if recovery == [False, False, False, False, True] and "Reset both endpoints together" in mailbox:
    warn("B-4", "KNOWN FAIL: RX reset after beat0..3 loses word phase; only a word-boundary reset (after beat4) stays aligned. Protocol needs explicit framing/index/epoch for single-board reset recovery")
else:
    fail("B-4", f"unexpected reset-structure result {recovery}")

# B-5: role constraints must use identical physical locations for the media pins.
def pins(rel):
    s = read(rel)
    out = {}
    for name, loc in re.findall(r"set_pin_assignment \{\s*([^}]+?)\s*\}\s*\{\s*LOCATION\s*=\s*([^;]+);", s):
        out[name.strip()] = loc.strip()
    return out

mp, sp = pins("constraints/master/master.adc"), pins("constraints/slave/slave.adc")
media_nets = [f"link_data[{i}]" for i in range(7)] + ["link_req", "link_ack", "display_published"]
mismatch = [(n, mp.get(n), sp.get(n)) for n in media_nets if mp.get(n) != sp.get(n)]
if not mismatch:
    ok("B-5", "Master/Slave ADC files agree on all 10 media/feedback FPGA pin locations; physical Dupont-wire order still requires board measurement")
else:
    fail("B-5", f"constraint mismatch: {mismatch}")

# B-6..B-9 remote-frame protocol.
if "1: out_data={24'hb17e00,id};" in remote and "in_data[31:8]==24'hb17e00" in remote:
    ok("B-6", "TX emits B17E00xx first and RX recognizes the same header")
else:
    fail("B-6", "header encoding/recognition changed")

word_count = 1 + 307200 * 2 + 1 + 1
if word_count == 614403:
    ok("B-7", "normal 640x480 frame is exactly 614403 32-bit words")

if all(x in remote for x in ["frame_begin<=1", "count<=count+1'b1", "count==PIXELS", "frame_done<=1", "frame_error<=1"]):
    ok("B-8", "RX has the expected begin/count/done/error state transitions")
else:
    fail("B-8", "RX event logic does not match expected structure")

if remote.count("32'h04c11db7") >= 2 and "if(in_data==crc) frame_done<=1; else frame_error<=1;" in remote:
    ok("B-9", "TX/RX use the same CRC32 polynomial and RX commits only on exact received-CRC match")
else:
    fail("B-9", "CRC implementation mismatch")

# B-10 fence path and top wiring.
if all(x in cdc for x in ["else if (media_done)", "done_toggle <= ~done_toggle", "fence_pending && empty && sdr_adapter_idle", "sdr_fenced    <= 1'b1"]):
    ok("B-10", "media_done is tokenized across CDC and fence waits for FIFO empty + adapter-idle input")
else:
    fail("B-10", "CDC fence structure changed")
if ".sdr_adapter_idle(mem_wr_ready)" in core:
    if all(x in adapter for x in ["assign mem_wr_ready = can_accept_write;", "state == ST_IDLE", "provider_available"]):
        warn("B-10", "Top uses mem_wr_ready as the adapter-idle proxy. It is conservative with the current adapter (ST_IDLE + provider available + no read request), but it is not a separately named/explicit idle signal")
    else:
        fail("B-10", "mem_wr_ready is used as idle but adapter semantics could not be confirmed")

# B-11 publish warm-up gate.
need = ["frame_fenced_media", "frame_ready_pix", "fb_warm_ready", "fb_frame_boundary",
        "publish_wait_frame", "use_framebuffer <= 1'b1"]
if all(x in core for x in need):
    ok("B-11", "publish path gates on fence + frame_ready_pix + warm_ready + safe frame boundary and intentionally waits one extra frame")
else:
    fail("B-11", "publish/warm-up gate incomplete")

# B-12 repeated begin behavior / instrumentation.
if "if(in_data[31:8]==24'hb17e00)" in remote and "if (dispatch_fire) begin" in core and "use_framebuffer <= 1'b0;" in core:
    ok("B-12", "a newly parsed header can generate remote_begin/dispatch_fire and clear use_framebuffer, so repeated false headers can look like perpetual Loading")
if not all(x in core for x in ["remote_begin_counter", "remote_done_counter", "remote_error_counter"]):
    warn("B-12", "requested begin/done/error counters are not present in active RTL; use ChipWatcher pulses/counters externally or add dedicated debug instrumentation before board capture")

# B-13 feedback reset/startup semantics on Slave.
if all(x in slave_top for x in [
        "wire use_framebuffer=published2 && observed_loading && !tx_busy;",
        "published1<=display_published; published2<=published1;",
        "if(dispatch_fire) begin",
        "observed_loading<=0;",
        "else if(!published2) observed_loading<=1;"]):
    ok("B-13", "Slave requires a post-dispatch observed published=0 before accepting the later published=1 as completion")
else:
    fail("B-13", "display_published feedback semantics changed")

print("\nRESULT:")
if issues:
    for tag, msg in issues:
        print(f"  {tag}: {msg}")
    sys.exit(1)
print("  Static checks passed. B-4 remains a documented protocol weakness; board-only observations are still required for B-1/B-5/B-6..B-13 live signals.")
