# ============================================================
# 时钟/时序约束 - 占位模板（以官方与综合报报告为准）
# ============================================================

create_clock -name clk_50m     -period 20.000 [get_ports clk_50m]     # 50MHz
create_clock -name clk_pix     -period 39.722 [get_ports clk_pix]     # 25.175MHz (640x480@60)
create_clock -name clk_tmds    -period 3.972  [get_ports clk_tmds]    # ~251.75MHz TMDS 位时钟
create_clock -name clk_sdram   -period 10.000 [get_ports clk_sdram]   # 100MHz
create_clock -name clk_sdo     -period 40.000 [get_ports clk_sdo]     # 25MHz SD
create_clock -name clk_aud     -period 81.380 [get_ports clk_aud]     # 12.288MHz 音频

# 时钟域间用异步 FIFO，时序上避免伪路径
# set_false_path -from [get_clocks clk_sys] -to [get_clocks clk_pix]

