# ================================================================
# dual_led 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/interact/run_dual_led.do
# ================================================================

vlib work
vlog ../src/interact/dual_led.v ../sim_tb/interact/tb_dual_led.v
vsim tb_dual_led
run -all
quit -f
