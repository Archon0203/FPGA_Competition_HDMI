# P1-02B · TD5.6.2 150 MHz timing closure candidate 2

Date: 2026-09-01

## 1. Candidate-1 validation evidence

The first 150 MHz cleanup candidate was revalidated at RTL level before this revision:

- `sdram_arbiter`: **PASS (checks=39)**
- `sdram_adapter`: **PASS (checks=61)**
- `sdram_arbiter_adapter_chain`: **PASS (checks=42)**
- P0 media chain: **PASS (checks=1698)**
- `p1_apug011_bist`: **PASS (checks=9)**
- P1-02A official APUG011 regression: **PASS (checks=24)**, tCK/tRCD/App read-DM/physical READ DQM violations all zero; addr5/addr8 read back correctly.

The automated TD5.6.2 CLI attempt was not usable because its generated worker Tcl lost the device database argument (`import_device -package` with an empty DB). This is a CLI environment/tool-flow issue and is not used as implementation evidence.

The same candidate was then run successfully in the **TD5.6.2 GUI** using SynOpt + PhyOpt. The GUI timing report is preserved under `docs/evidence/` and shows:

- constrained clock: `u_apug011_ref_pll/pll_inst.clkc[1]`
- target period: **6.666 ns (150 MHz)**
- setup errors: **3**
- setup TNS: **-0.127 ns**
- reported setup slack / TNS summary: **-0.127 ns**
- hold errors: **0**, hold TNS **0.000 ns**
- minimum period: **6.793 ns**
- maximum frequency: **147.210 MHz**
- timing endpoints: 528; analyzed paths: 12168; coverage: 87.47%

Thus candidate 1 materially improved the original baseline (9 setup errors, WNS -0.460 ns, TNS -1.357 ns, minimum period 7.126 ns) but did **not** close 150 MHz timing. P1-02B remains a timing failure until setup errors reach zero.

## 2. Candidate-2 RTL change

Only `src/framebuf/sdram_adapter.v` is changed in this candidate.

The v0.3 adapter maintained `read_outstanding_debug` using a 17-bit combinational add/subtract expression (`outstanding_next`) followed by carry/borrow inspection on every cycle. Candidate 2 replaces that expression with the equivalent two-event sequential update:

- accepted P0 read only -> increment;
- returned target response only -> decrement;
- simultaneous accept + target response -> hold;
- neither -> hold.

The existing explicit underflow detector is retained. Overflow is structurally unreachable because APUG011 reads are serialized in 4-word groups and the response-tag FIFO bounds in-flight provider words far below a 16-bit P0 outstanding count.

This is deliberately a low-risk timing cleanup: no interface, request/response ordering, APUG011 protocol, PLL, SDC, 150 MHz target, protected source, or BIST behavior is changed.

## 3. Evidence status after the source change

Because `sdram_adapter` changed from v0.3 to v0.4, its previous PASS(61) and every regression that contains it are historical evidence only until rerun on candidate 2. `sdram_arbiter` itself is unchanged from candidate 1 and its PASS(39) remains valid for that module revision.

P1-02B is **not** `[S]` yet. Candidate 2 must first preserve all RTL regressions and then complete TD5.6.2 GUI SynOpt/PhyOpt with:

- setup errors = 0
- setup WNS >= 0
- setup TNS = 0
- hold errors = 0
- hold slack >= 0
- hold TNS = 0

No clock relaxation is permitted.

## 4. Required validation

Run the six regression benches in the same order used for candidate 1. Since `sdram_adapter` changed, all six should be rerun rather than relying on the previous transcript.

Then use **TD5.6.2 GUI** (not the currently broken CLI worker flow) to run SynOpt + PhyOpt + BitGen on the existing project. Keep `constraints/p1_apug011_td.sdc` unchanged at 6.666 ns / 150 MHz.

If timing still fails, export the complete remaining setup-path table (slack, source, destination, logic level, data path, launch/capture clock). The path table is required before making a third structural timing change.

## 5. Final candidate-2 validation — CLOSED

Candidate 2 was rerun without changing RTL, SDC, PLL, or vendor protected sources. The complete required RTL regression passed:

- `sdram_arbiter`: **PASS (checks=39)**
- `sdram_adapter` v0.4: **PASS (checks=61)**
- strict `sdram_arbiter_adapter_chain`: **PASS (checks=42)**
- P0 media chain: **PASS (checks=1698)**
- `p1_apug011_bist`: **PASS (checks=9)**
- P1-02A official APUG011 regression: **PASS (checks=24)**
  - tCK violations = 0
  - tRCD violations = 0
  - application read-DM violations = 0
  - physical READ DQM violations = 0
  - addr5 readback = `0x11223344`
  - addr8 readback = `0xA5A55A5A`

TD5.6.2 / V5.6.71036 GUI implementation also completed successfully:

- SynOpt: PASS, `gate.db` generated, no ERROR
- protected `sdr_as_ram`, `sdr_init_ref`, `sdr_wrrd`: expanded, not black boxes
- `EG_PHY_PLL`: recognized
- `EG_PHY_SDRAM_2M_32`: recognized and physically legalized as the EG internal SDRAM macro, not BRAM
- PhyOpt: place + route PASS, `place.db` and `pr.db` generated
- BitGen: PASS, valid `FPGA_Competition_HDMI.bit` generated
- 150 MHz target remained **6.666 ns**; no clock relaxation was used

Final timing for `u_apug011_ref_pll/pll_inst.clkc[1]`:

| Metric | Final result |
|---|---:|
| Target period | 6.666 ns |
| Setup errors | **0** |
| Setup WNS | **+0.059 ns** |
| Setup TNS | **0.000 ns** |
| Minimum period | **6.607 ns** |
| Maximum frequency | **151.355 MHz** |
| Hold errors | **0** |
| Minimum hold slack | **+0.260 ns** |
| Hold TNS | **0.000 ns** |

All nine setup-failing paths from the original baseline disappeared. The new worst setup path is legal and positive-slack:

- source: `u_adapter/provider_fault_reg_syn_12.clk`
- destination: `u_bist/reg1_syn_28`
- launch/capture: `clkc[1]`
- logic level: 6
- reported data-path delay: 8.762 ns
- setup slack: **+0.059 ns**

Final resources:

- LUT: **283 (1.44%)**
- REG: **243 (1.24%)**
- LE: **377**
- PLL: **1 (25%)**
- GCLK: **1 (6.25%)**
- BRAM: **0**
- BRAM32K: **0**

Warnings are non-blocking vendor/tool informational warnings only: `HDL-5007 x2` from `encrypted_text(0)` unsized literals and `SYN-5055 x10` kept-net merges. Synthesis and physical-design logs contain zero ERRORs.

## 6. Closure decision

**P1-02A = `[C-sub] PASS`** and **P1-02B = `[S] PASS`**.

The APUG011 SDRAM backend integration is therefore closed at the TD synthesis/P&R/timing evidence level. This status is intentionally limited to the TD-only 25 MHz reference-clock harness; it does not claim the final HX4S20C 50 MHz board-top pin build or real-board operation, which remain P1-04/P1-05 evidence boundaries.
