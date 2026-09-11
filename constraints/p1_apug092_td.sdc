# ============================================================================
# P1-03B APUG092 clock-injected TD synthesis/P&R harness constraints.
# This is NOT the HX4S20C final board SDC.
#
# P1-03B transport baseline: 1280x720 progressive, 60 Hz class timing
#   Htotal = 1650, Vtotal = 750
#   pixel  = 74.25 MHz  -> 13.468013 ns
# APUG092 official clock architecture:
#   serial = 5 * pixel  -> 371.25 MHz -> 2.693603 ns
#
# The supplied APUG092 source uses the same 1280x720 timing constants, while
# its PH1A-only generated PLL must not be reused on EG4S20.  This harness uses
# explicit top-level clocks so TD can characterize the protected APUG092 + EG
# PHY boundary independently from the later HX4S20C board PLL.
#
# The two clocks are physically injected and have no generated-clock relation
# in this harness.  Treat them as exclusive just as the vendor reference SDC
# does.  P1-04 must replace this with the real EG PLL/generated-clock topology.
# ============================================================================

create_clock -name p1_hdmi_pixel  -period 13.468013 -waveform {0 6.7340065} [get_ports {P1_PIXEL_CLK}]
create_clock -name p1_hdmi_serial -period 2.693603  -waveform {0 1.3468015} [get_ports {P1_SERIAL_CLK}]

set_clock_groups -exclusive -group [get_clocks {p1_hdmi_pixel}] -group [get_clocks {p1_hdmi_serial}]
