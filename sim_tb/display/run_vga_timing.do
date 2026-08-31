# ================================================================
# vga_timing 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/display/run_vga_timing.do
# ================================================================

vlib work
vlog ../src/display/vga_timing.v ../sim_tb/display/tb_vga_timing.v
vsim tb_vga_timing
run -all
quit -f

