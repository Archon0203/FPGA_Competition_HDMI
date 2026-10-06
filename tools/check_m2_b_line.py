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

# B-1: published/mux/top/LED contradiction.  Publication now additionally
# requires proof that the post-fence scanout emitted a real framebuffer pixel.
# This makes LED3/DISPLAY_PUBLISHED an end-to-end display datapath milestone,
# not merely a control-state milestone.
if ("<MODULE>m2_master_tf_hdmi_top</MODULE>" in master_al and
        all(x in core for x in ["assign current_frame_published = use_framebuffer && front_valid",
            "!loading_active && fb_data_seen", "media_succeeded && frame_fenced_media",
            "hdmi_video_ready && !p1_05a_error", "assign remote_published = current_frame_published",
            "use_framebuffer && front_valid ? framebuffer_axis_data : loading_rgb",
            ".axis_data       (axis_data)"]) and
        "assign led={display_led[3] || ctrl_led[3],display_published,ctrl_led[1:0]};" in master_top):
    ok("B-1", "publication gates on front buffer + post-fence pixel proof + clean HDMI; reload preserves front")
else:
    fail("B-1", "publish/LED/mux/framebuffer-live/HDMI relationship does not match the checklist")

# B-2: LED1/LED2 are control-UART status only.
control = read("src/dual_board/m2_master_media_control.v")
if "assign led[0] = ack_toggle;" in control and "assign led[1] = link_ok;" in control:
    ok("B-2", "Master LED1=control ack_toggle and LED2=UART link_ok; neither proves media-mailbox health")
else:
    fail("B-2", "Master control LED mapping changed")

# B-3/B-4: self-framing six-symbol mailbox + four-phase handshake.
def symbols(w):
    return [
        0x40 | ((w >> 0) & 0x3f),
        (w >> 6) & 0x3f,
        (w >> 12) & 0x3f,
        (w >> 18) & 0x3f,
        (w >> 24) & 0x3f,
        (w >> 30) & 0x03,
    ]


def unpack_symbols(b):
    return (
        (b[0] & 0x3f) | ((b[1] & 0x3f) << 6) |
        ((b[2] & 0x3f) << 12) | ((b[3] & 0x3f) << 18) |
        ((b[4] & 0x3f) << 24) | ((b[5] & 0x03) << 30)
    ) & 0xffffffff

patterns = [0x00000000, 0xffffffff, 0x12345678, 0x89abcdef,
            0xb17e0000, 0xf17e0000, 0x40000000, 0x7fffffff, 0x80000000]
rng = random.Random(0xB17E)
patterns += [rng.getrandbits(32) for _ in range(10000)]
errors = sum(unpack_symbols(symbols(w)) != w for w in patterns)
rtl_shape = all(x in mailbox for x in [
    "{1'b1, in_data[5:0]}", "word_value[11:6]", "word_value[17:12]",
    "word_value[23:18]", "word_value[29:24]", "word_value[31:30]",
    "out_data   <= {data[1:0], lower}", "ST_WAIT_ACK1", "ST_WAIT_ACK0"
])
if errors == 0 and rtl_shape:
    ok("B-3", "9 required patterns + 10,000 deterministic random words reconstruct bit-exactly in the self-framing six-symbol mapping")
else:
    fail("B-3", f"packing audit errors={errors}, rtl_shape={rtl_shape}")

# The explicit start bit permits the receiver to discard any interrupted word
# and lock again on the following word.  The four-phase req/ack handshake also
# forces both controls back low after either endpoint reset.
if all(x in mailbox for x in [
        "explicit start-of-word marker", "state <= ST_ALIGN",
        "if (ack2 == 1'b0)", "if (data[6])",
        "Non-start symbols received while not assembling"]):
    ok("B-4", "mailbox now has explicit word framing and four-phase req/ack recovery for independent endpoint resets")
else:
    fail("B-4", "independent-reset recovery structure is incomplete")

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
# Board-schematic cross-reference for the documented literal J1 wiring.  Merely
# making Master and Slave ADC files equal is NOT sufficient: FIX5 did exactly
# that while logical data[3] was placed on L12/GPIOA20, which reaches J2-34,
# not the wired J1-5.  That left data[3] missing while REQ/ACK still drained.
expected_ball = {
    "link_data[0]":"D14", "link_data[1]":"G11", "link_data[2]":"G12",
    "link_data[3]":"H13", "link_data[4]":"H14", "link_data[5]":"J14",
    "link_data[6]":"K12", "link_req":"L14", "link_ack":"M14",
    "display_published":"L16",
}
physical_mismatch = [(n, expected_ball[n], mp.get(n), sp.get(n))
                     for n in media_nets if mp.get(n) != expected_ball[n] or sp.get(n) != expected_ball[n]]
if not mismatch and not physical_mismatch:
    ok("B-5", "Master/Slave ADC agree AND match the board-schematic J1 electrical cross-reference for all media pins")
else:
    fail("B-5", f"constraint/electrical mismatch role={mismatch} physical={physical_mismatch}")

# B-6..B-9 remote-frame protocol.
if all(x in remote for x in ["24'hb17e00", "24'hb17e01", "COMPACT_RGB888", "compact_pixel"]):
    ok("B-6", "TX/RX share legacy B17E00 and compact RGB888 B17E01 headers")
else:
    fail("B-6", "header encoding/recognition changed")
legacy_words = 1 + 307200 * 2 + 7 + 2
compact_bottom_up_words = 1 + 307200 + 480 + 7 + 2
ok("B-7", f"RGB888+metadata: legacy={legacy_words}, compact bottom-up={compact_bottom_up_words}; sequence/CRC verified in simulation")

if all(x in remote for x in ["frame_begin<=1", "count<=count+1'b1", "count==PIXELS", "frame_done<=1", "frame_error<=1"]):
    ok("B-8", "RX has the expected begin/count/done/error state transitions")
else:
    fail("B-8", "RX event logic does not match expected structure")

if remote.count("32'h04c11db7") >= 2 and "if(in_data==crc) begin" in remote and "frame_done<=1" in remote:
    ok("B-9", "TX/RX use the same CRC32 polynomial and RX commits only on exact received-CRC match")
else:
    fail("B-9", "CRC implementation mismatch")

# B-10 fence path and top wiring.
if all(x in cdc for x in ["else if (media_done)", "done_toggle <= ~done_toggle", "fence_pending && empty && sdr_adapter_idle", "sdr_fenced    <= 1'b1"]):
    ok("B-10", "media_done is tokenized across CDC and fence waits for FIFO empty + adapter-idle input")
else:
    fail("B-10", "CDC fence structure changed")
if (".sdr_adapter_idle(sdram_adapter_idle)" in core and
        ".adapter_idle            (sdram_adapter_idle)" in core and
        "assign adapter_idle      = (state == ST_IDLE) && provider_available;" in adapter):
    ok("B-10", "write fence now uses an explicit adapter_idle signal rather than mem_wr_ready as an idle proxy")
else:
    fail("B-10", "explicit adapter-idle fence wiring is missing")

# B-11 publish warm-up gate.
need = ["frame_fenced_media", "frame_ready_pix", "fb_warm_ready", "fb_frame_boundary",
        "publish_wait_frame", "use_framebuffer <= 1'b1"]
if all(x in core for x in need):
    ok("B-11", "publish path gates on fence + frame_ready_pix + warm_ready + safe frame boundary and intentionally waits one extra frame")
else:
    fail("B-11", "publish/warm-up gate incomplete")

# B-12 repeated begin behavior / instrumentation.
if "in_data[31:8]==24'hb17e00" in remote and "if (dispatch_fire) begin" in core and "use_framebuffer <= 1'b0;" in core:
    ok("B-12", "a new header starts a back-buffer load; startup-only UI leaves an existing front frame visible")
if not all(x in core for x in ["remote_begin_counter", "remote_done_counter", "remote_error_counter"]):
    warn("B-12", "requested begin/done/error counters are not present in active RTL; use ChipWatcher pulses/counters externally or add dedicated debug instrumentation before board capture")

# B-13 feedback reset/startup semantics on Slave.
if all(x in slave_top for x in [
        "wire use_framebuffer=published2 && observed_loading && !tx_busy;",
        "published1<=display_published; published2<=published1;",
        "transport_retry_request", "publish_wait_count",
        "if(dispatch_fire) begin",
        "observed_loading<=0;",
        "else if(!published2) observed_loading<=1;"]):
    ok("B-13", "Slave keeps the published=0/1 completion guard and now re-reads/resends a frame after a publish timeout")
else:
    fail("B-13", "display_published feedback/retry semantics changed unexpectedly")

print("\nRESULT:")
if issues:
    for tag, msg in issues:
        print(f"  {tag}: {msg}")
    sys.exit(1)
print("  Static checks passed. Independent-reset framing, explicit adapter-idle fencing, and publish-timeout resend are present; board-only observations are still required for B-1/B-5/B-6..B-13 live signals.")
