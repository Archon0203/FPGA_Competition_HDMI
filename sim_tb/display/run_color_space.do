# ================================================================
# color_space 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/display/run_color_space.do
# ================================================================

vlib work
vlog ../src/display/color_space.v ../sim_tb/display/tb_color_space.v
vsim tb_color_space
run -all
quit -f
