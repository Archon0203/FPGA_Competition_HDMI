# ============================================================================
# P1-04B HX4S20C board-safe HDMI_B smoke-test timing constraints
#
# Source of truth: user's physically working official lab_ex4_tf project.
#   board clock : 50 MHz
#   PLL C0      : 25 MHz pixel
#   PLL C1      : 125 MHz serial
#
# Derived clocks are intentionally obtained from EG_PHY_PLL itself.
# ============================================================================

create_clock -name hx4s20c_clk50m -period 20.000 -waveform {0 10.000} [get_ports {clk}]
derive_pll_clocks
