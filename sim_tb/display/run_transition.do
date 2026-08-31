# ================================================================
# transition 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/display/run_transition.do
# ================================================================

vlib work
vlog ../src/display/transition.v ../sim_tb/display/tb_transition.v
vsim tb_transition
run -all
quit -f
