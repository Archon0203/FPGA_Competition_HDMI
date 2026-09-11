# ============================================================================
# P1-04A HX4S20C 50 MHz -> EG PLL -> APUG092 720p smoke-top timing constraints
#
# Board oscillator: 50 MHz / 20 ns.
# p1_hdmi_pll_50m candidate outputs:
#   C0: 75 MHz pixel clock, 0 deg
#   C1: 375 MHz serial clock, 90 deg
#
# Do NOT hand-create C0/C1 clocks here. Let TD derive them from EG_PHY_PLL so
# the report proves what the instantiated primitive actually generated.
# ============================================================================

create_clock -name hx4s20c_clk50m -period 20.000 -waveform {0 10.000} [get_ports {I_CLK_50M}]
derive_pll_clocks
