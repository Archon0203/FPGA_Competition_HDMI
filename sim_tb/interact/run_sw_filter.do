# ================================================================
# sw_filter 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/interact/run_sw_filter.do
# ================================================================

vlib work
vlog ../src/interact/sw_filter.v ../sim_tb/interact/tb_sw_filter.v
vsim tb_sw_filter
run -all
quit -f
