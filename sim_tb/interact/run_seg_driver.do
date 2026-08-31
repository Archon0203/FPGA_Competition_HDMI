# ================================================================
# seg_driver 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/interact/run_seg_driver.do
# ================================================================

vlib work
vlog ../src/interact/seg_driver.v ../sim_tb/interact/tb_seg_driver.v
vsim tb_seg_driver
run -all
quit -f
