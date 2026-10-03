# 50 MHz board oscillator; generated clocks are derived from the instantiated EG PLLs.
create_clock -name hx4s20c_clk50m -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
derive_clocks

# M2 media/display CDC policy inherited from the board-proven P1-05A build.
# The 25 MHz pixel/media domain and 150 MHz SDRAM controller domain cross only
# through explicit async FIFOs / synchronizers; do not time them as synchronous.
set_clock_groups -asynchronous \
    -group [get_clocks {u_hdmi_pll/u_pll.clkc[0]}] \
    -group [get_clocks {u_sdram_pll/pll_inst.clkc[1]}]

# APUG011 hard-macro phase-boundary exceptions, copied from the proven
# p1_hx4s20c_hdmi_board.sdc.  clkc[1] is the 150 MHz controller clock;
# clkc[2] is the 180-degree SDRAM hard-macro launch clock. TD6.2.1 otherwise
# models the fixed EG_PHY_SDRAM_2M_32 DQ boundary as impossible half-cycle
# ordinary register paths.  These exceptions are deliberately limited to the
# two APUG011 phase-related PLL outputs; 150 MHz controller RTL remains timed.
set_false_path \
    -from [get_clocks {u_sdram_pll/pll_inst.clkc[2]}] \
    -to [get_clocks {u_sdram_pll/pll_inst.clkc[1]}]

set_false_path \
    -from [get_clocks {u_sdram_pll/pll_inst.clkc[1]}] \
    -to [get_clocks {u_sdram_pll/pll_inst.clkc[2]}]
