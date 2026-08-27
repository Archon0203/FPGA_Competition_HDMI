# ================================================================
# vga_timing 仿真并记录波形（必须加 -novopt 保留层次信号）。
# 在 sim_work 目录运行：
#   vsim -c -novopt -wlf ../sim_work/wave_vga_timing.wlf tb_vga_timing -do ../sim_tb/display/run_vga_timing_wave.do
# 然后用 ModelSim GUI 打开 wave_vga_timing.wlf 查看。
# ================================================================

add wave -r /tb_vga_timing/u_dut/*
run -all
quit -f

