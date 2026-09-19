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

Until those are complete, the previous P1-05A `[S][B] CLOSED` evidence remains the TD5.6.2 historical baseline, not a new TD6.2.1 closure claim.
