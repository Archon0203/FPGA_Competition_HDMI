# P1-02B TD-only APUG011 synthesis/P&R harness clock constraint.
# This is NOT an HX4S20C board pin constraint.
# It mirrors the APUG011 v1.2 official reference PLL input: 25 MHz.
create_clock -name p1_refclk_25m -period 40 -waveform {0 20} [get_ports {REF_CLK_25M}]

# derive_pll_clocks is the command valid in both TD 5.6.2 and TD 6.2.1;
# TD 6.2.1 only marks it obsolete but still accepts it. Interpolate the PLL
# outputs (12.5 MHz / 150 MHz 0 deg / 150 MHz 180 deg) from the 25 MHz ref.
derive_pll_clocks
