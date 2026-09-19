# P1-02B · TD5.6.2 150 MHz timing closure candidate

Date: 2026-09-01

## 1. Baseline evidence before this candidate

The current project was cleanly revalidated with **Anlogic TD 5.6.2 / V5.6.71036** without changing RTL, SDC, or protected vendor sources.

- `tb_p1_apug011_bist`: **PASS (checks=9)**.
- P1-02A official APUG011 + official IS42 regression: **PASS (checks=24)**.
- TD synthesis: **PASS**, 0 errors; `sdr_as_ram`, `sdr_init_ref`, `sdr_wrrd` expanded; `EG_PHY_PLL` and `EG_PHY_SDRAM_2M_32` recognized.
- Physical Design: **place + route + bitgen completed**, valid `.bit` produced.
- 150 MHz generated clock remained constrained at 6.666 ns.
- Final timing: **setup FAIL**, 9 endpoints, WNS `-0.460 ns`, TNS `-1.357 ns`; hold 0 errors, minimum hold slack `+0.260 ns`.
- All 9 setup failures were on project-owned BIST/arbiter/adapter control paths. No setup failure was inside the protected APUG011 controller. Protected-core hold paths remained positive.

This means the vendor protected core, PLL, EG internal SDRAM primitive, TD source organization, implementation flow, and bit generation are already proven usable. The remaining blocker is a shallow project-owned 150 MHz control cone.

## 2. Candidate changes

### 2.1 `p1_apug011_td_top`: one-entry registered request slice

A one-entry valid/ready request slice was inserted **only in the P1-02B TD/BIST harness** between `p1_apug011_bist` and `sdram_arbiter`.

Purpose:

- break the decoded BIST-state -> arbiter -> adapter setup cone;
- hold request type/address/data stable until the arbiter accepts it;
- keep BIST functional semantics unchanged;
- avoid changing the frozen P0 memory interface or the arbiter/adapter interfaces.

The slice is not part of the final media datapath contract. It is a synthesis-observability/test-harness timing boundary.

### 2.2 `sdram_arbiter`: remove redundant 17-bit add/subtract/compare error cone

The outstanding-read update was rewritten as the equivalent event case `{rd_accept,response_legal}`. `rd_outstanding_debug` now directly observes the registered outstanding count.

The previous `outstanding_next > MAX_READ_OUTSTANDING` check was redundant because `mem_rd_valid` is already gated by `read_credit`; therefore a read cannot be accepted when the configured outstanding limit is exhausted. Removing the redundant arithmetic/comparison cone prevents downstream `ready` from feeding a long non-functional path into the sticky `protocol_error` register.

The external valid/ready behavior, strict read priority, zero-latency response legality, unsolicited-response detection, counters, and outstanding semantics are intended to remain unchanged.

## 3. Evidence status

Do **not** award P1-02B `[S]` from this source change alone.

The existing BIST result is sufficient to mark `p1_apug011_bist` itself `[U]`, because that module was not changed by this timing candidate. However, `sdram_arbiter` changed and therefore its previous unit/chain evidence must be re-run before carrying its `[U]` evidence forward to this revision.

P1-02B becomes `[S]` only after TD5.6.2 completes clean synthesis + P&R and the final 150 MHz setup/hold timing is non-negative. P1-02 as a whole is an integration milestone, so `[U]` is not the correct final label for the milestone; `[U]` applies to unit modules, while P1-02B's target evidence is `[S]`.

## 4. Required validation

Run, in order:

1. `sdram_arbiter` unit regression.
2. `sdram_adapter` unit regression.
3. strict arbiter -> adapter chain regression.
4. P0 full media-chain regression (because the P0 arbiter RTL changed).
5. P1-02B BIST unit regression.
6. P1-02A official protected-core regression.
7. TD5.6.2 clean Synthesis + Physical Design + bitgen.
8. Inspect final generated clocks/resources/setup/hold timing and all warnings/errors.

The decisive result is final TD timing at 150 MHz. The desired result is setup errors=0 and hold errors=0 without changing the 6.666 ns clock target.
