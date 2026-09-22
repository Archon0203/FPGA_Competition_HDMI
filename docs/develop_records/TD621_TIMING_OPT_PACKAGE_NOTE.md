# TD6.2.1 timing-optimization package note

This package contains the project source/configuration after the 2026-09-17 TD6.2.1 timing-optimization pass.

Two RTL changes are included:

1. `p1_sdram_cached_adapter` has `ENABLE_RUNTIME_DIAGNOSTICS`; the board top sets it to `0` so non-data-path debug counters/redundant assertions do not consume the production 150 MHz timing cone. Default `1` is retained for existing simulation testbenches.
2. HDMI reset release in `p1_hx4s20c_sdram_hdmi_top` uses the 50 MHz rising edge, matching the official board reference. The falling-edge experiment was reverted because TD6.2.1 reports a recovery violation in the 125 MHz serial domain. The hold duration remains approximately 20 ms.

The container used for this package does not have the TD6.2.1 executable, so no new synthesis/P&R/BitGen result is included. Existing generated TD runs were deliberately excluded because they belong to the pre-optimization netlist and would be stale.

Required validation on the official environment:

- TD6.2.1 full synthesis + P&R + final STA
- Questa regression
- BitGen
- HX4S20C board validation

At package creation time, the previous P1-05A `[S][B] CLOSED` evidence remained the TD5.6.2 historical baseline, not a new TD6.2.1 closure claim. The subsequent official-environment result is recorded below.

## Subsequent official-environment verification — 2026-09-21

The official TD6.2.1 environment later completed the package validation for the active P1-05A top. The routed final report is `FPGA_Competition_HDMI_Runs/phy_1/final_timing.rpt`:

```text
Generated       2026-09-21 11:40:27
STA coverage    99.17%
SWNS            +0.599 ns
STNS            0.000 ns
HWNS            +0.003 ns
HTNS            0.000 ns
violating endpoints: setup 0, hold 0
```

BitGen generated `FPGA_Competition_HDMI_Runs/phy_1/FPGA_Competition_HDMI.bit`. This establishes the current TD6.2.1 routed `[S]` result. No new TD6.2.1 board observation is recorded here, so the `[B]` evidence remains the historical P1-05A framebuffer demonstration. The run still reports two unhonored `u_internal_sdram` initial locations and one clock net using local routing resources; these warnings remain open implementation risks.
