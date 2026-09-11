// ================================================================
// Module  : p1_hdmi_pll_50m
// Purpose : P1-04A EG4S20 clock candidate for the APUG092 720p
//           board bring-up path.
//
// Input : HX4S20C board oscillator, 50.000 MHz.
// Output: pixel_clk  = 75.000 MHz, 0 deg
//         serial_clk = 375.000 MHz, 90 deg
//
// Why 75/375 instead of an invented board clock pair:
//   The supplied APUG092 reference package's generated PLL explicitly uses
//   75 MHz pixel and 375 MHz serial clocks, with the serial clock shifted
//   by 90 degrees.  Its protected transmitter is configured for 1280x720.
//   This project therefore follows that vendor bring-up clock pair first.
//
// EG PLL construction:
//   REFCLK_DIV = 2, FBCLK_DIV = 3, external C0 feedback.
//   C0 divider = 15 -> 75 MHz, and is the feedback clock.
//   VCO = 50/2 * 3 * 15 = 1125 MHz, inside the EAGLE PLL guide's
//   documented 300..1200 MHz VCO range.
//   C1 divider = 3 -> 375 MHz; CPHASE=2/FPHASE=6 matches the phase
//   encoding used by the supplied APUG092 375 MHz/90 deg reference PLL.
//
// IMPORTANT verification boundary:
//   The divider/phase topology is source-derived and deterministic, but the
//   analog loop-filter tuning fields below are taken from the official
//   EG4S20 TD5.6.2 APUG011 generated PLL (nearby 1050 MHz VCO).  Before this
//   clock block can earn [S]/[B], regenerate/inspect the accompanying IPC in
//   TD5.6.2 and compare the generated EG_PHY_PLL analog parameters, then run
//   PLL lock + timing + real-monitor tests.  Do not treat this file alone as
//   board-proven clock evidence.
// ================================================================

`timescale 1 ns / 100 fs

module p1_hdmi_pll_50m (
    input  wire refclk_50m,
    input  wire reset,
    output wire lock,
    output wire pixel_clk,
    output wire serial_clk
);

    wire pixel_clk_raw;
    wire [4:0] pll_clkc;
    wire [7:0] pll_do_unused;
    wire       psdone_unused;

    // C0 is both the 75 MHz pixel clock and the external feedback path,
    // mirroring the structure of Anlogic-generated EAGLE PLL wrappers.
    EG_LOGIC_BUFG u_pixel_bufg (
        .i(pixel_clk_raw),
        .o(pixel_clk)
    );

    EG_PHY_PLL #(
        .DPHASE_SOURCE ("DISABLE"),
        .DYNCFG        ("DISABLE"),
        .FIN           ("50.000"),
        .FEEDBK_MODE   ("NORMAL"),
        .FEEDBK_PATH   ("CLKC0_EXT"),
        .STDBY_ENABLE  ("DISABLE"),
        .PLLRST_ENA    ("ENABLE"),
        .SYNC_ENABLE   ("DISABLE"),
        .DERIVE_PLL_CLOCKS("DISABLE"),
        .GEN_BASIC_CLOCK  ("DISABLE"),

        // Candidate analog tuning. See module header / IPC note.
        .GMC_GAIN       (0),
        .ICP_CURRENT    (9),
        .KVCO           (2),
        .LPF_CAPACITOR  (2),
        .LPF_RESISTOR   (8),

        .REFCLK_DIV     (2),
        .FBCLK_DIV      (3),

        .CLKC0_ENABLE   ("ENABLE"),
        .CLKC0_DIV      (15),
        .CLKC0_CPHASE   (14),
        .CLKC0_FPHASE   (0),

        .CLKC1_ENABLE   ("ENABLE"),
        .CLKC1_DIV      (3),
        .CLKC1_CPHASE   (2),
        .CLKC1_FPHASE   (6)
    ) u_pll (
        .refclk  (refclk_50m),
        .reset   (reset),
        .stdby   (1'b0),
        .extlock (lock),

        .load_reg(1'b0),
        .psclk   (1'b0),
        .psdown  (1'b0),
        .psstep  (1'b0),
        .psclksel(3'b000),
        .psdone  (psdone_unused),

        .dclk    (1'b0),
        .dcs     (1'b0),
        .dwe     (1'b0),
        .di      (8'h00),
        .daddr   (6'h00),
        .do      (pll_do_unused),

        .fbclk   (pixel_clk),
        .clkc    (pll_clkc)
    );

    assign pixel_clk_raw = pll_clkc[0];
    assign serial_clk    = pll_clkc[1];

endmodule
