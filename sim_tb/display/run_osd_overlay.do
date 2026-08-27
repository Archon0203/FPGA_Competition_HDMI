# ================================================================
# osd_overlay 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/display/run_osd_overlay.do
# ================================================================

vlib work
vlog ../src/display/osd_overlay.v ../sim_tb/display/tb_osd_overlay.v
vsim tb_osd_overlay
run -all
quit -f
