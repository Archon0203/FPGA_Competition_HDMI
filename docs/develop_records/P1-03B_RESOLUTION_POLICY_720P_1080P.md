# P1-03B Resolution Policy · 720p baseline / 1080p feasibility gate

Date: 2026-09-10

## Decision

- Physical HDMI transport baseline is raised to **1280×720** now.
- Existing P0 640×480 regressions remain frozen; they are content/framebuffer tests, not the final HDMI transport requirement.
- A 1920×1080 parameter profile is kept in the APUG092 TD harness, but no 1080p `[S]`/`[B]` claim is allowed until the EG output board proves the required clock and PHY timing.

## Vendor evidence that drove the decision

The supplied APUG092 package has two relevant pieces of evidence:

1. `design_top_wrapper.v` configures the active protected transmitter core as 1280×720 (`1650×750`) with internal TPG enabled. This is the practical reference path and is why the project no longer accepts 640×480 as its HDMI output target.
2. The APUG092 user guide explains 1080p60 using 2200×1125 total timing, 148.5 MHz Pixel Clock and a 5× 742.5 MHz Serial Clock. It also lists 1920×1080/VIC16 as default core parameters.

## Memory capacity

The EG4S20 internal SDRAM is 2M×32 words.

```text
720p RGB888 stored in one 32-bit word/pixel:
1280 × 720 =   921,600 words/frame
A+B       = 1,843,200 words
capacity  = 2,097,152 words
margin    =   253,952 words
```

Therefore native 720p A/B buffering is capacity-feasible on one board.

```text
1080p:
1920 × 1080 = 2,073,600 words/frame
capacity    = 2,097,152 words
```

Only one full 1080p RGB888 frame nearly fills the SDRAM, so native A/B double buffering is impossible without changing storage architecture.

## Why a second board is not yet a 1080p solution

A second HX4S20C can potentially help with frame storage, preprocessing, TF bandwidth, or line-stream partitioning. It does **not** remove the final output-board requirement:

```text
1920×1080p60 APUG092
pixel clock  = 148.5 MHz
serial clock = 742.5 MHz
```

Whatever board drives the HDMI connector must still meet that serializer/PLL/IO timing. Therefore the correct order is:

```text
1. close 720p APUG092 + EG PHY
2. generate/bind real EG 720p PLL and HDMI pins
3. board-test 720p
4. create a TD-only 1080p clock/PHY feasibility harness
5. only if 742.5 MHz is viable, choose single-board streaming vs dual-board partition
```

This avoids a large architecture rewrite before the actual bottleneck is known.
