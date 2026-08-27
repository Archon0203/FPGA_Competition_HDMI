# ================================================================
# reset_gen 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/top/run_reset_gen.do
# ================================================================

vlib work
vlog ../src/top/reset_gen.v ../sim_tb/top/tb_reset_gen.v
vsim tb_reset_gen
run -all
quit -f
