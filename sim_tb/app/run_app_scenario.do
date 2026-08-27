# ================================================================
# app_scenario 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/app/run_app_scenario.do
# ================================================================

vlib work
vlog ../src/app/app_scenario.v ../sim_tb/app/tb_app_scenario.v
vsim tb_app_scenario
run -all
quit -f
