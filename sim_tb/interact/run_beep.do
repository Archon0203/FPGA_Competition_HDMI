# ================================================================
# beep 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/interact/run_beep.do
# ================================================================

vlib work
vlog ../src/interact/beep.v ../sim_tb/interact/tb_beep.v
vsim tb_beep
run -all
quit -f
