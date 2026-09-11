# P1-03A · `hdmi_video_adapter` APUG092 video-contract candidate

Date: 2026-09-10

## 1. Scope

This iteration implements the next project-owned P1 module after P1-02 closure:

```text
line_buffer_pingpong
        ↓ display-order continuous RGB888 line
hdmi_video_adapter
        ↓ APUG092 Video Interface
I_axis_s_user / valid / last / data + O_axis_s_ready
```

It deliberately stops at the APUG092 application-side video boundary. The encrypted APUG092 core, EG HDMI PHY, pixel/serial PLL, HX4S20C HDMI pins and final board top are **not** claimed complete in P1-03A.

## 2. Official APUG092 facts used

Source: user-provided `APUG092_HDMI1.4b_Transmitter_V1.0` official Anlogic package.

The official documentation states:

- Video Interface is in the Pixel Clock domain.
- `I_axis_s_user` is a one-cycle frame-start indication on the first valid pixel of the first active line.
- `I_axis_s_valid` marks valid active-video data.
- `I_axis_s_last` is asserted at the end of each line.
- `O_axis_s_ready=1` means input can be accepted.
- Critically, `O_axis_s_ready` only deasserts after `I_axis_s_last`; external video input does **not** support discontinuous data within a line. One active line must be supplied continuously.
- External video is used only when `VIDEO_TPG="Disable"`.
- RGB and YUV444 8-bit input formats are supported.
- APUG092 PHY reference uses `serial_clk = 5 × pixel_clk` plus DDR serialization; the official `hdmi_phy_wrapper` supports `DEVICE="EG"` and selects `EG_LOGIC_ODDR`.

These facts match the frozen P0 reason for `line_prefetcher + line_buffer_pingpong`: an active line must not underflow into valid gaps.

## 3. New RTL

`src/display/hdmi_video_adapter.v`

Responsibilities:

1. At a legal line boundary, wait for `axis_ready=1` before requesting a line from `line_buffer_pingpong`.
2. Request `ACTIVE_WIDTH` pixels for `current_line`.
3. Forward RGB888 without byte reordering.
4. Generate APUG092 markers:
   - `axis_user` only on frame pixel `(line=0, x=0)`;
   - `axis_last` only on pixel `x=ACTIVE_WIDTH-1` for every active line.
5. Advance lines and wrap after `ACTIVE_HEIGHT`.
6. Emit `frame_done_pulse` after the final active pixel of the frame.
7. Sticky-detect broken project/provider contracts:
   - `axis_ready` drops inside an active line;
   - `lb_pixel_valid` has a gap after line streaming begins;
   - `lb_line_done` does not coincide with the configured final pixel.

The adapter does **not** gate an in-progress line by `axis_ready`. This is intentional: APUG092 documents ready as line-boundary backpressure, while the P0 line-buffer output is not stallable once a line begins.

## 4. Verification added

### Unit TB

```powershell
cd sim_work
vsim -c -do ../sim_tb/display/run_hdmi_video_adapter.do
```

Required checks:

- no line request while APUG092 `ready=0`;
- exact line index/width requests;
- continuous full-frame pixel count;
- exactly one SOF/user per frame;
- exactly one EOL/last per line;
- legal ready-low gaps between lines do not start a line early;
- second frame wraps to line 0 and produces SOF again;
- illegal mid-line `ready` drop sets `protocol_error`;
- illegal line-buffer `pixel_valid` gap sets `protocol_error`.

### Project-owned sub-chain TB

```powershell
cd sim_work
vsim -c -do ../sim_tb/integration/run_hdmi_video_linebuffer_chain.do
```

This connects the real `line_buffer_pingpong` to `hdmi_video_adapter`, preloads two known RGB lines, then checks RGB preservation, SOF/EOL positions, exact beat count and absence of underflow/protocol error.

## 5. Vendor reference subset

Copied unchanged from the official package into:

```text
src/vendor/anlogic/apug092/
```

Files:

- `hdmi_1_4b_transmitter_core_wrapper.enc.v`
- `hdmi_phy_warpper.v`
- `lane_lvds_10_1.v`
- `APUG092_SOURCE_INFO.txt`

They remain reference/read-only. P1-03B now binds them in a **separate clock-injected TD harness** (`FPGA_Competition_HDMI_P1-03B.al`) without reusing the PH1A reference PLL or pin file. The real EG4S20 PLL and HX4S20C board pins are still deferred to P1-04, so no board constraint has been guessed.

## 6. Status gate

Current source state is **candidate / unverified**.

After both new QuestaSim tests pass, `hdmi_video_adapter` may become `[U]`, and the real `line_buffer_pingpong -> hdmi_video_adapter` project-owned boundary may become `[C-sub]`.

This still does not award P1-03 `[B]`: real APUG092 protected-core behavior, EG PHY/PLL TD implementation, and monitor output remain to be verified.
