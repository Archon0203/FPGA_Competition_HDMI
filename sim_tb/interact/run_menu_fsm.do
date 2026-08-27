# ================================================================
# menu_fsm 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/interact/run_menu_fsm.do
# ================================================================

vlib work
vlog ../src/interact/menu_fsm.v ../sim_tb/interact/tb_menu_fsm.v
vsim tb_menu_fsm
run -all
quit -f
