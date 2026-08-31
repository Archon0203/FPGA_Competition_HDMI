# ================================================================
# image_scaler 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/display/run_image_scaler.do
# ================================================================

vlib work
vlog ../src/display/image_scaler.v ../sim_tb/display/tb_image_scaler.v
vsim tb_image_scaler
run -all
quit -f
