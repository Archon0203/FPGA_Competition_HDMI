# P1-04B HX4S20C official-640 board-safe HDMI candidate

Date: 2026-09-11

## Why P1-04B exists

P1-04A proved that the project-owned HDMI application path synthesizes, but its experimental 75/375 MHz clock point did not close timing in TD5.6.2. The same read-only test round also established a stronger board-level source of truth: the user's physically working official `lab_ex4_tf` project on the actual HX4S20C board and monitor.

P1-04B therefore stops guessing and reproduces the known-good official board point before any further 720p optimization.

## Frozen board facts imported from the working sample

- Device: `EG4S20BG256`
- Board oscillator: 50 MHz, `R7`, `LVCMOS33`
- Physical connector: HDMI_B
- Video: 640x480, HTOTAL=800, VTOTAL=525, VIC=1
- Horizontal porch/sync/back: 16 / 96 / 48
- Vertical porch/sync/back: 10 / 2 / 33
- Pixel clock: 25 MHz @ 0deg
- Serial clock: 125 MHz @ 0deg
- Serial/pixel ratio: 5

HDMI_B physical mappings:

| Signal | Pin | IOSTANDARD |
|---|---|---|
| TMDS D0 P | G5 | LVDS33 |
| TMDS D1 P | F1 | LVDS33 |
| TMDS D2 P | E1 | LVDS33 |
| TMDS CLK P | C3 | LVDS33 |
| DDC SCL | P2 | LVCMOS33 |
| DDC SDA | R2 | LVCMOS33 |

The top deliberately does not use KEY1/KEY2. The official project maps KEY1=B2 and KEY2=C1, but the user observed the board labels may be physically swapped; that is kept as a separate physical-confirmation issue.

## PLL source of truth

`src/top/p1_hdmi_pll_50m_25_125.v` uses the exact PLL fields reported from the physically working official `video_pll.v`:

```
FIN             = 50.000000
REFCLK_DIV      = 2
FBCLK_DIV       = 1
FEEDBK_MODE     = NORMAL
FEEDBK_PATH     = CLKC0_EXT
CLKC0_DIV       = 40
CLKC0_CPHASE    = 39
CLKC0_FPHASE    = 0
CLKC1_DIV       = 8
CLKC1_CPHASE    = 7
CLKC1_FPHASE    = 0
GMC_GAIN        = 2
ICP_CURRENT     = 9
KVCO            = 2
LPF_CAPACITOR   = 1
LPF_RESISTOR    = 8
```

No P1-04A 75/375 analog/phase values are reused.

## Board-safe top

New top: `src/top/p1_hx4s20c_hdmi_board_top.v`

```
50 MHz clk
  -> official-matched EG PLL (25/125 MHz)
  -> 640x480 color-bar whole-line provider
  -> hdmi_video_adapter
  -> APUG092 protected transmitter
  -> official EG hdmi_phy_wrapper
  -> HDMI_B
```

Only the six physically verified board I/O signals are top-level outputs/inputs. Project debug signals remain internal so P1-04B does not invent LED/button pin assignments.

## Constraints / TD project

- `constraints/p1_hx4s20c_hdmi_board.sdc`
- `constraints/p1_hx4s20c_hdmi_board.adc`
- `FPGA_Competition_HDMI_P1-04B.al`

The ADC is no longer a template. It contains the working sample's real HX4S20C HDMI_B mappings and is intended for TD P&R/BitGen validation.

## Resolution policy

640x480 here is not a regression in final ambition. It is the board-safe bring-up point and exactly matches the user's working official sample, satisfying the requirement that our first demonstrated output not be lower than the official baseline.

The 720p branch remains active, but P1-04A proved that the current hand-written 75/375 clock candidate is not timing-closed. After P1-04B is physically proven, 720p will be reopened as a controlled PLL/STA optimization problem instead of being mixed with pin/core/board bring-up.

1080p/double-board work remains deferred until a single-board high-rate APUG092 PHY feasibility result exists.

## Required verification before [B]

1. TD5.6.2 SynOpt: no errors / no unresolved or black-box design nodes.
2. Derived clocks: 25 MHz and 125 MHz, both 0deg, ratio 5.
3. PhyOpt: setup/hold/removal all non-negative.
4. BitGen succeeds with the real ADC.
5. Program the board only after items 1-4 pass.
6. Real monitor: stable 640x480 eight-color bars on HDMI_B for at least 10 minutes; hot replug once; power cycle once.
7. Do not use KEY1/KEY2 in this test.

P1-04B remains **candidate** until the above evidence returns.
