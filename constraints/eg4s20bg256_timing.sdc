# ============================================================
# Generic timing placeholder - NOT an active board constraint set.
# Replace/derive clocks from the final TD5.6.2 EG PLL in P1-04.
# ============================================================

create_clock -name clk_50m       -period 20.000 [get_ports clk_50m]       # HX4S20C board oscillator target
create_clock -name clk_pix       -period 39.722 [get_ports clk_pix]       # HISTORICAL placeholder: 25.175 MHz / 640x480
create_clock -name clk_hdmi_ser  -period 7.944  [get_ports clk_hdmi_ser]  # HISTORICAL placeholder: 125.875 MHz = 5 * pixel
create_clock -name clk_sdram     -period 6.666  [get_ports clk_sdram]     # 150 MHz APUG011 hardware target
create_clock -name clk_sdo       -period 40.000 [get_ports clk_sdo]       # 25 MHz SD target
create_clock -name clk_aud       -period 81.380 [get_ports clk_aud]       # 12.288 MHz audio target

# Final false-path/clock-group policy must be based on the real generated
# clocks and CDC structure.  Do not use this placeholder for board BitGen.
