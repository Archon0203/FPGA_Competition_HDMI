# P1-02B · TD 6.2.1 native protected-source integration note

## Evidence that changed the integration strategy

Using the untouched APUG011 v1.2 reference project copy in TD 6.2.1 Engineer 168116:

- set `sdr_as_ram.enc.v` / module `sdr_as_ram` as Top;
- remove the demo-only `io.adc` because its `SYS_CLK -> T14` assignment belongs to the original demo Top, not to `sdr_as_ram`;
- run Syn Opt;
- observed **0 ERROR** (warnings remain to be classified when reviewing the main-project report).

Therefore the protected APUG011 RTL is readable/synthesizable by TD 6.2.1 in this environment. The former main-project `undeclared symbol '**'` / `unknown module sdr_as_ram` / black-box failure was caused by the project-owned `apug011_td_compile_unit.v` approach, not by a demonstrated APUG011 IP-license deficiency.

## Required TD organization

Mirror the official APUG011 project:

1. `src/vendor/anlogic/apug011/include/global_def.v`
   - independent project source;
   - `GlobalIncluded=true`;
   - compile order 1.
2. `sdr_as_ram.enc.v`, `sdr_init_ref.enc.v`, `sdr_wrrd.enc.v`
   - independent Verilog project sources;
   - never concatenated or textually included by project RTL.
3. `src/top/apug011_td_compile_unit.v`
   - deprecated audit stub only;
   - not listed in `FPGA_Competition_HDMI.al`.
4. Vendor files remain byte-for-byte read-only.

## Evidence boundary

This note does **not** award `[S]`.  `[S]` still requires the project-level P1-02B harness to complete TD synthesis + P&R and then inspect timing, resources, PLL/generated clocks, `EG_PHY_SDRAM_2M_32`, RAM inference, and constraints.


## Syn Opt evidence and TD6.2 timing-command update

Project-level `syn_1` has now completed `read_design/opt_rtl/opt_gate` and produced a gate DB with the protected APUG011 hierarchy and EG SDRAM/PLL primitives recognized. This removes the former black-box blocker. The captured pre-P&R timing had setup WNS=-5958 ps (115 failing endpoints) and hold WNS=+549 ps; these values are **not final `[S]` evidence** because Physical Design has not completed.

TD 6.2.1 GUI reports `derive_pll_clocks` as obsolete and explicitly recommends `derive_clocks`. The P1-02B SDC therefore uses `derive_clocks` from this candidate onward. Re-run Syn Opt before comparing timing, then judge timing only from a completed P&R result. Do not lower the 150 MHz requirement merely to make the report green.

The current `phy_1` absence is recorded as a tool-flow blockage after a run reset, not as a design P&R failure. A clean GUI Syn Opt -> Physical Design run is the preferred next experiment.
