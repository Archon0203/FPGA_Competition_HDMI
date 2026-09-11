# P1-03B · APUG092 protected core + EG PHY integration candidate

Date: 2026-09-10  
Revision: 720p transport baseline

## 1. Scope

P1-03A created the project-owned `hdmi_video_adapter`; P1-03B connects that interface to the official protected APUG092 transmitter and the official `hdmi_phy_wrapper(DEVICE="EG")` without yet binding the HX4S20C board PLL or physical HDMI pins.

```text
hdmi_test_pattern_line_provider
        ↓ whole-line RGB888 contract
hdmi_video_adapter
        ↓ user / valid / last / RGB888 / ready
apug092_core_wrapper
        ↓ official protected APUG092 10-bit TMDS words
apug092_tx_wrapper
        ↓ official hdmi_phy_wrapper(DEVICE="EG")
EG_LOGIC_ODDR
        ↓
TMDS positive outputs
```

The standalone color-bar provider is deliberate: HDMI/core/PHY bring-up can be debugged before SDRAM/TF/scaling are allowed into the failure surface.

## 2. Resolution decision: P1-03B is no longer 640×480

The supplied APUG092 reference source is important here:

- its `design_top_wrapper.v` instantiates the protected transmitter core with **1280×720** timing (`1650×750` total);
- its internal test pattern is enabled, therefore that protected-core timing—not the otherwise-present external `video_source_test` instance—is the active reference HDMI path;
- the same source uses `VIDEO_VIC=69` for that 1280×720 instance;
- the bundled generated PH1A PLL produces 75 MHz pixel / 375 MHz serial clocks, while APUG092's documented architecture requires serial clock = 5 × pixel clock.

The APUG092 user guide separately uses **1920×1080p60** as its clock-calculation example/default parameter set and gives 148.5 MHz pixel / 742.5 MHz serial clocks. This proves that the core interface is parameterized for 1080p; it does **not** by itself prove that EG4S20 + HX4S20C can meet the corresponding PHY/PLL timing.

Project policy is therefore:

```text
P1-03/P1-04 physical HDMI transport baseline = 1280×720
P0 legacy framebuffer regression geometry     = 640×480 (unchanged/frozen)
1080p                                          = compile-time profile only until P&R + board evidence
```

This avoids lowering the HDMI transport below the supplied APUG092 reference while avoiding a premature P0 rewrite.

## 3. 720p timing used by this candidate

The protected core is configured with the same 1280×720 geometry as the supplied APUG092 source:

```text
HACTIVE = 1280
HFP     = 110
HSA     = 40
HBP     = 220
HTOTAL  = 1650

VACTIVE = 720
VFP     = 5
VSA     = 5
VBP     = 20
VTOTAL  = 750

VIDEO_VIC = 69   (mirrors supplied APUG092 reference source)
```

For the clock-injected TD harness we constrain the transport to the 74.25 MHz / 371.25 MHz pair associated with 1650×750 at 60 frames/s:

```text
pixel  = 74.25 MHz
serial = 371.25 MHz = 5 × pixel
```

The supplied PH1A PLL is not copied because it instantiates PH1 primitives. P1-04 must generate and validate an EG PLL from the HX4S20C 50 MHz board clock.

## 4. Compile-time 1080p profile added without committing to feasibility

`p1_apug092_td_top` now has:

```verilog
parameter integer VIDEO_MODE = 0;
```

Profiles:

```text
VIDEO_MODE=0 : 1280×720 baseline, VIC 69
VIDEO_MODE=1 : 1920×1080 profile, VIC 16
```

The 1080p profile only changes APUG092 timing parameters and project-side line-source/adapter geometry. It intentionally does **not** change the P1-03B SDC, generate a 742.5 MHz serial clock, or claim board support.

The reason is architectural: a second EG4S20 board can add storage/processing/bandwidth partitioning, but a single HDMI output board still has to serialize a full 1080p stream. Therefore dual-board work does not remove the APUG092/EG-PHY 742.5 MHz feasibility requirement. That must be measured before a major two-board refactor.

## 5. Why 720p does not require reopening P0 now

P1-03B is isolated from the framebuffer and produces 720p color bars, so the P0 freeze remains valid.

For later native 720p framebuffer work, the existing address model is still structurally usable:

```text
1280 × 720 = 921,600 32-bit words/frame
2 frames   = 1,843,200 words
EG4S20 internal SDRAM capacity = 2,097,152 words
```

Thus two native RGB888-in-32-bit 720p framebuffers fit in the internal 2M×32 SDRAM, leaving 253,952 words. The existing frame-buffer manager already parameterizes physical buffer bases, so native 720p should be a controlled P1-05/P2 migration rather than a wholesale rewrite. The old P0 regression continues to use `IMAGE_B_BASE=307200` until that migration is deliberately opened and reverified.

By contrast, one 1920×1080 RGB888 frame consumes 2,073,600 words, nearly the entire SDRAM; two full 1080p framebuffers do not fit. This is a genuine reason to consider streaming, reduced storage format, or a second board later.

## 6. Project-owned RTL in this candidate

### `src/display/hdmi_test_pattern_line_provider.v`

Synthesizable whole-line provider producing eight vertical color bars. It uses the same contract as `line_buffer_pingpong`, allowing the HDMI transport to be tested independently from SDRAM.

### `src/top/apug092_core_wrapper.v`

Stable wrapper around the protected APUG092 core:

- `DEVICE="EG"`;
- `VIDEO_TPG="Disable"` so project external RGB is used;
- `VIDEO_FORMAT="RGB"`;
- default geometry changed to 1280×720;
- audio/ACR/EDID ports retained for later stages.

### `src/top/apug092_tx_wrapper.v`

Protected APUG092 core + official EG HDMI PHY. Clock generation remains outside the wrapper by design.

### `src/top/p1_apug092_td_top.v`

Clock-injected TD harness with 720p default and dormant 1080p compile-time profile. It is not a board top.

## 7. Pending verification

No status promotion is made because Questa/Codex verification is currently deferred.

### Project RTL

```powershell
cd sim_work
vsim -c -do ../sim_tb/display/run_hdmi_video_adapter.do
vsim -c -do ../sim_tb/integration/run_hdmi_video_linebuffer_chain.do
vsim -c -do ../sim_tb/display/run_hdmi_test_pattern_line_provider.do
```

### Protected APUG092 external-video chain

```powershell
cd sim_work
vsim -c -do ../sim_tb/integration/run_apug092_external_video_core.do
```

This TB now runs a real 1280×720 external-video stream into the protected core and stops before the EG ODDR simulation boundary.

### TD5.6.2 harness

Open:

```text
FPGA_Competition_HDMI_P1-03B.al
```

Expected active clocks:

```text
p1_hdmi_pixel  : 74.25 MHz  / 13.468013 ns
p1_hdmi_serial : 371.25 MHz / 2.693603 ns
```

Required evidence is protected-core/EG-PHY elaboration, SynOpt/PhyOpt, resources, setup/hold timing and `EG_LOGIC_ODDR` recognition. A successful result is vendor-integration evidence only; board `[B]` still requires the real EG PLL and physical HDMI/DDC binding in P1-04.
