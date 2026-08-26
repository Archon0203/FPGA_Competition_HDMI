# ================================================================
# vga_timing 仿真（记录波形，用于 GUI 查看）。
# 在 sim_tb 目录执行（必须加 -novopt 以保留层次信号）：
#   vsim -c -novopt -wlf wave_vga_timing.wlf tb_vga_timing -do ../sim/run_vga_timing_wave.do
# 然后在 ModelSim GUI 打开 sim_tb/wave_vga_timing.wlf 查看波形。
# ================================================================

add wave -position insertpoint /tb_vga_timing/u_dut/hs
add wave -position insertpoint /tb_vga_timing/u_dut/vs
add wave -position insertpoint /tb_vga_timing/u_dut/de
add wave -position insertpoint /tb_vga_timing/u_dut/hcnt
add wave -position insertpoint /tb_vga_timing/u_dut/vcnt
add wave -position insertpoint /tb_vga_timing/u_dut/pixel_x
add wave -position insertpoint /tb_vga_timing/u_dut/pixel_y
run -all
quit -f
