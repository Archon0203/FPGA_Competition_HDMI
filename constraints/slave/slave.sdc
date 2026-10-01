# 50 MHz board oscillator; generated 25/125 MHz HDMI clocks come from the
# same EG PLL wrapper used by the board-proven P1-04C baseline.
create_clock -name hx4s20c_clk50m -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
derive_clocks
