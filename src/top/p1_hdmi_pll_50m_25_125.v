// ================================================================
// Module  : p1_hdmi_pll_50m_25_125
// Purpose : P1-04B board-safe HDMI clock block for HX4S20C.
//
// Source of truth:
//   Parameters below are copied from the user's physically working
//   official HX4S20C lab_ex4_tf/lab_ex5_i2s_v1.0 video_pll.v report.
//   Board input:  50 MHz
//   Pixel clock:  25 MHz, 0 deg
//   Serial clock: 125 MHz, 0 deg
//
// This module deliberately does NOT reuse the experimental P1-04A 75/375
// candidate.  P1-04B first reproduces the known-good official board clock
// point so APUG092 + EG PHY + real HX4S20C pins can be validated safely.
// ================================================================

`timescale 1 ns / 100 fs

module p1_hdmi_pll_50m_25_125 (
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

    // The working official design uses CLKC0_EXT feedback.  Buffer C0 and
    // feed the buffered clock back to the primitive, matching the established
    // EAGLE PLL wrapper structure used elsewhere in this project.
    EG_LOGIC_BUFG u_pixel_bufg (
        .i(pixel_clk_raw),
        .o(pixel_clk)
    );

    EG_PHY_PLL #(
        .DPHASE_SOURCE ("DISABLE"),
        .DYNCFG        ("DISABLE"),
        .FIN           ("50.000000"),
        .FEEDBK_MODE   ("NORMAL"),
        .FEEDBK_PATH   ("CLKC0_EXT"),
        .STDBY_ENABLE  ("DISABLE"),
        .PLLRST_ENA    ("ENABLE"),
        .SYNC_ENABLE   ("DISABLE"),
        .DERIVE_PLL_CLOCKS("DISABLE"),
        .GEN_BASIC_CLOCK  ("DISABLE"),

        // Exact analog tuning values reported from the working official
        // HX4S20C video_pll.v.
        .GMC_GAIN       (2),
        .ICP_CURRENT    (9),
        .KVCO           (2),
        .LPF_CAPACITOR  (1),
        .LPF_RESISTOR   (8),

        .REFCLK_DIV     (2),
        .FBCLK_DIV      (1),

        .CLKC0_ENABLE   ("ENABLE"),
        .CLKC0_DIV      (40),
        .CLKC0_CPHASE   (39),
        .CLKC0_FPHASE   (0),

        .CLKC1_ENABLE   ("ENABLE"),
        .CLKC1_DIV      (8),
        .CLKC1_CPHASE   (7),
        .CLKC1_FPHASE   (0)
    ) u_pll (
        .refclk   (refclk_50m),
        .reset    (reset),
        .stdby    (1'b0),
        .extlock  (lock),

        .load_reg (1'b0),
        .psclk    (1'b0),
        .psdown   (1'b0),
        .psstep   (1'b0),
        .psclksel (3'b000),
        .psdone   (psdone_unused),

        .dclk     (1'b0),
        .dcs      (1'b0),
        .dwe      (1'b0),
        .di       (8'h00),
        .daddr    (6'h00),
        .do       (pll_do_unused),

        .fbclk    (pixel_clk),
        .clkc     (pll_clkc)
    );

    assign pixel_clk_raw = pll_clkc[0];
    assign serial_clk    = pll_clkc[1];

endmodule
