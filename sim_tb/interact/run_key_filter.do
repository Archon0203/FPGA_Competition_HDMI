# ================================================================
# key_filter 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/interact/run_key_filter.do
# ================================================================

vlib work
vlog ../src/interact/key_filter.v ../sim_tb/interact/tb_key_filter.v
vsim tb_key_filter
run -all
quit -f
