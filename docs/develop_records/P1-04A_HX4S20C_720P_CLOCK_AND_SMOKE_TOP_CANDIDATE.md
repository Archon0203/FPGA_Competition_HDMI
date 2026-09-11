# P1-04A · HX4S20C 50 MHz → APUG092 720p board-clock smoke-top candidate

Date: 2026-09-10  
Tool target: Anlogic TD 5.6.2 / EG4S20BG256  
Status: **candidate; no `[S]` or `[B]` claim yet**

## 1. Scope

P1-04A removes the two artificial top-level HDMI clocks used by the P1-03B TD harness and introduces the real board-clock boundary:

```text
HX4S20C 50 MHz
  -> p1_hdmi_pll_50m
      -> 75 MHz pixel
      -> 375 MHz serial, 90 deg
  -> color-bar line provider
  -> hdmi_video_adapter
  -> protected APUG092
  -> official EG HDMI PHY
```

SDRAM and TF are intentionally not in this top. The first board HDMI experiment must isolate clock/core/PHY/pin problems from storage problems.

## 2. Why the clock pair is 75 / 375 MHz

The supplied APUG092 v1.0 reference package contains a generated PLL whose comments specify:

```text
Input: 25 MHz
C0: 75 MHz, 0 deg
C1: 375 MHz, 90 deg
```

The same reference top configures the protected transmitter for 1280×720 (`1650×750`) and uses the same `hdmi_phy_wrapper` architecture. P1-04A therefore follows this vendor bring-up pair rather than inventing a different board-clock pair.

The P1-03B injected-clock harness remains a protocol/core boundary experiment; P1-04A is now the source of truth for the board-clock candidate.

## 3. EG4 PLL topology

`p1_hdmi_pll_50m.v` uses EAGLE external C0 feedback:

```text
FIN            = 50 MHz
REFCLK_DIV     = 2
FBCLK_DIV      = 3
C0_DIV         = 15 -> 75 MHz
C1_DIV         = 3  -> 375 MHz
C1 phase       = 90 deg
VCO            = 1125 MHz
```

The EAGLE PLL guide supplied by the user states an input range of 10–500 MHz, VCO range of 300–1200 MHz, and reference/feedback/output divider ranges of 1–128. The above divider topology is therefore structurally within those documented ranges.

### Analog-tuning caveat

The primitive's analog fields are provisionally copied from the official EG4S20 TD5.6.2 APUG011 generated PLL, whose VCO is 1050 MHz. An IPC file is provided at:

```text
ip/p1_hdmi_pll_50m_75_375.ipc
```

Before `[S]`/`[B]`, TD5.6.2 must regenerate or inspect this PLL and confirm the tool-selected analog parameters. If generated fields differ, replace only the project-owned `p1_hdmi_pll_50m.v` primitive parameters with the TD-generated values; do not modify APUG092 protected sources.

## 4. Reset policy

The smoke top intentionally has no push-button reset. The available conversation files do not contain the working HX4S20C `lab_ex4_tf` board ADC, and the user reports that KEY1/KEY2 labels appear reversed in that official sample.

The PLL starts without external reset. `pll_lock` directly qualifies the vendor APUG092/PHY reset, matching the supplied reference style. Project-owned line-provider/adapter logic receives a 256-pixel-clock delayed synchronous reset release through `reset_gen`.

This removes a board-key mapping ambiguity from the first HDMI test.

## 5. Board-pin boundary

No package locations are guessed. `constraints/p1_hx4s20c_hdmi_smoke.adc.template` names the required logical ports but contains no real locations.

P1-04B must import the mappings from the user's **known-working** official `lab_ex4_tf` project. This is safer than deriving pins from unrelated PH1A APUG092 constraints or third-party projects.

## 6. Required deferred verification

When Codex/Questa/TD testing is available:

1. run all P1-03A/P1-03B RTL regressions already queued;
2. in TD5.6.2, validate/regenerate `p1_hdmi_pll_50m_75_375.ipc`;
3. open `FPGA_Competition_HDMI_P1-04A.al` and run SynOpt first;
4. confirm `EG_PHY_PLL`, protected APUG092 and four `EG_LOGIC_ODDR` lanes elaborate;
5. inspect derived clocks: 75 MHz and 375 MHz, with no unconstrained internal reg-to-reg paths;
6. only after importing the official lab_ex4_tf ADC, run final PhyOpt/BitGen;
7. first board display target: stable 1280×720 vertical color bars;
8. then merge the SDRAM line-prefetch path.

## 7. 1080p boundary

No dual-board refactor is opened in P1-04A. 1080p still requires the final HDMI board to sustain the APUG092 5× serial clock and associated ODDR/routing. The 720p smoke build is deliberately the measurement platform used before deciding whether the 1080p/dual-board branch is technically justified.
