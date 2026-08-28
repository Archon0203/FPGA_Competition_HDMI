# ================================================================
# tmds_encoder 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/display/run_tmds_encoder.do
# ================================================================

vlib work
vlog ../src/display/tmds_encoder.v ../sim_tb/display/tb_tmds_encoder.v
vsim tb_tmds_encoder
run -all
quit -f
