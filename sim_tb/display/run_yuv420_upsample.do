# ================================================================
# yuv420_upsample 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/display/run_yuv420_upsample.do
# ================================================================

vlib work
vlog ../src/display/yuv420_upsample.v ../sim_tb/display/tb_yuv420_upsample.v
vsim tb_yuv420_upsample
run -all
quit -f
