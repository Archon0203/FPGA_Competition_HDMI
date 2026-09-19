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
# TD6.2.1 supersedes derive_pll_clocks with derive_clocks.  The latter keeps
# the same generated PLL clock names while also deriving non-PLL clocking
# resources used by the protected APUG011/HDMI blocks.
derive_clocks

# ============================================================================
# P1-05A timing closure candidate 2
# 25 MHz pixel and 150 MHz SDRAM domains intentionally cross only through
# explicit CDC structures (async FIFO / synchronizers).  Do not time those
# crossings as single-cycle synchronous paths.
# Clock names below are the exact derived-clock names reported by TD5.6.2.
# ============================================================================
set_clock_groups -asynchronous \
    -group [get_clocks {u_hdmi_pll/u_pll.clkc[0]}] \
    -group [get_clocks {u_sdram_pll/pll_inst.clkc[1]}]

# APUG011 uses clkc[1] (150 MHz, 0 deg) for controller logic and clkc[2]
# (150 MHz, 180 deg) only to launch the SDRAM hard macro clock.  The official
# APUG011 v1.2 TD5.6.2 reference reports no timing endpoints for this macro
# return path.  TD6.2.1 instead models its 32 DQ return pins as ordinary
# half-cycle paths from clkc[2] to clkc[1], yielding an impossible 3.333 ns
# budget through the fixed EG_PHY_SDRAM_2M_32 macro.  Exclude only that
# generated hard-macro direction; controller logic remains timed at 150 MHz.
set_false_path \
    -from [get_clocks {u_sdram_pll/pll_inst.clkc[2]}] \
    -to [get_clocks {u_sdram_pll/pll_inst.clkc[1]}]

# The companion direction is the APUG011 controller's registered SDRAM DQ
# output-enable bus into EG_PHY_SDRAM_2M_32.  TD6.2.1 models the hard macro
# boundary as a regular half-cycle register path even though SDRAM_CLK is the
# phase-shifted external-memory launch clock.  Keep both exceptions limited to
# the two APUG011 phase-related PLL outputs; all controller-domain paths stay
# constrained at 150 MHz.
set_false_path \
    -from [get_clocks {u_sdram_pll/pll_inst.clkc[1]}] \
    -to [get_clocks {u_sdram_pll/pll_inst.clkc[2]}]
