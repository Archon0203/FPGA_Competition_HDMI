# ================================================================
# image_enhance 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/display/run_image_enhance.do
# ================================================================

vlib work
vlog ../src/display/image_enhance.v ../sim_tb/display/tb_image_enhance.v
vsim tb_image_enhance
run -all
quit -f

