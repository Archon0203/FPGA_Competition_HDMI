# P1-02B · TD 6.2.1 P&R retry note

## Current evidence

- Native protected-source organization works; no `sdr_as_ram` black box blocker.
- `syn_1` previously completed read_design/opt_rtl/opt_gate and emitted gate DB.
- Protected hierarchy and EG primitives were recognized.
- Pre-P&R setup timing failed; hold passed.
- `phy_1` has no valid result because a reset/relaunch left the worker stuck during initialization. This is **FLOW BLOCKED**, not a P&R FAIL.

## Change in this candidate

`constraints/p1_apug011_td.sdc` now uses:

```tcl
create_clock -name p1_refclk_25m -period 40 -waveform {0 20} [get_ports {REF_CLK_25M}]
derive_clocks
```

TD 6.2.1 explicitly reports `derive_pll_clocks` as obsolete. No RTL or vendor protected file is changed for this fix.

## Recommended clean GUI run

1. Open this candidate as a clean project in TD 6.2.1 Engineer 168116.
2. Confirm TOP=`p1_apug011_td_top`, ADC empty, SDC=`constraints/p1_apug011_td.sdc`.
3. Run Syn Opt from GUI and save its report. Do not reuse timing from the obsolete-command run.
4. If Syn Opt completes, run Physical Design/P&R from GUI without issuing `reset_runs syn_1 -f` in parallel.
5. If P&R completes, collect final setup/hold WNS/TNS, unconstrained paths, resources, generated clocks and primitive legalization.
6. If the GUI worker again stops after only its banner, capture the worker/run log and process status; do not modify RTL or vendor IP merely to recover the tool process.

## Acceptance

`[S]` requires completed synthesis **and** P&R plus reviewed timing/resources/RAM-or-SDRAM primitive/clock constraints. A successful Syn Opt alone, or pre-P&R negative slack alone, does not settle `[S]`.
