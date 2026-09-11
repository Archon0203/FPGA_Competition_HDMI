# P1-03 verification queue and 2026-09-11 results

Original queue date: 2026-09-10

Update 2026-09-11: Codex/Questa became available and the queued project-owned tests were executed. This document is retained as the verification plan plus returned evidence rather than a still-pending list.

Returned results:
- `hdmi_video_adapter`: PASS(24)
- `line_buffer_pingpong -> hdmi_video_adapter`: PASS(57)
- `hdmi_test_pattern_line_provider`: PASS(37)
- line_buffer regression: PASS(2204)
- line_prefetcher regression: PASS(2713)
- APUG092 protected behavioral simulation: TOOL_BLOCKED at Questa optimization in protected region; vlog Errors=0
- TD5.6.2 P1-04A SynOpt: PASS, but 75/375MHz timing FAIL
- working official lab_ex4_tf board facts were extracted and used to create P1-04B.

## A. Project-owned RTL regression

Run from `sim_work`:

```powershell
vsim -c -do ../sim_tb/display/run_hdmi_video_adapter.do
vsim -c -do ../sim_tb/integration/run_hdmi_video_linebuffer_chain.do
vsim -c -do ../sim_tb/display/run_hdmi_test_pattern_line_provider.do
```

Also protect the P0 display source:

```powershell
vsim -c -do ../sim_tb/framebuf/run_line_buffer_pingpong.do
vsim -c -do ../sim_tb/framebuf/run_line_prefetcher.do
```

Historical protected expectations for the last two are `PASS(2204)` and `PASS(2713)`.

## B. Protected APUG092 behavioral integration

```powershell
vsim -c -do ../sim_tb/integration/run_apug092_external_video_core.do
```

Required evidence:

- at least one full external-video frame completes;
- `hdmi_test_pattern_line_provider.protocol_error=0`;
- `hdmi_video_adapter.protocol_error=0`;
- protected APUG092 `O_video_locked=1` within the TB timeout;
- 10-bit TMDS parallel words show activity;
- no mid-line `O_axis_s_ready` violation is observed by the adapter.

If `O_video_locked` does not assert, return the full transcript and waveforms for `axis_ready/user/valid/last`, current line/pixel and `O_video_locked`; do not edit protected vendor RTL.

## C. TD5.6.2 P1-03B harness

Open `FPGA_Competition_HDMI_P1-03B.al`, not the P1-02 closed project.

Expected configuration:

```text
Device = EG4S20BG256
TOP = p1_apug092_td_top
SDC = constraints/p1_apug092_td.sdc
ADC = none
Pixel clock target = 13.468013 ns (74.25 MHz)
Serial clock target = 2.693603 ns (371.25 MHz)
```

Run SynOpt and PhyOpt. BitGen is optional for this harness because no board pins/real PLL are bound; a successful bit file would still not be board-runnable.

Collect:

- synthesis/physical ERROR and WARNING classification;
- protected APUG092 elaboration status;
- `EG_LOGIC_ODDR` count/recognition;
- LUT/REG/ERAM/GCLK usage;
- setup/hold timing for both clock groups;
- unconstrained paths;
- whether TMDS/DDC top outputs are preserved.

Do not promote this harness to final `[S]` board status. It only establishes the vendor/EG-PHY integration boundary.

## D. P1-04A result / P1-04B board-safe implementation

P1-04A SynOpt recognized 50/75/375 MHz as intended, but STA returned setup, hold and removal violations. It is therefore frozen as a non-board-safe 720p timing experiment.

The requested P1-04B evidence was then obtained from the exact official `lab_ex4_tf` project that the user physically verified. P1-04B now imports those facts directly:

- 50 MHz `clk`: R7/LVCMOS33;
- HDMI_B D0/D1/D2/CLK P: G5/F1/E1/C3, LVDS33;
- DDC SCL/SDA: P2/R2, LVCMOS33;
- 640x480/800x525/VIC1 timing;
- working EG PLL: 25 MHz pixel + 125 MHz serial, both 0deg, with full reported analog/divider parameters.

Implemented files:
- `p1_hdmi_pll_50m_25_125.v`;
- `p1_hx4s20c_hdmi_board_top.v`;
- `p1_hx4s20c_hdmi_board.sdc`;
- `p1_hx4s20c_hdmi_board.adc`;
- `FPGA_Competition_HDMI_P1-04B.al`.

Next evidence is now TD5.6.2 SynOpt/PhyOpt/timing/BitGen. Only after timing is closed should the resulting bitstream be downloaded for a 640x480 color-bar board smoke test. KEY1/KEY2 are deliberately not used.
