# ================================================================
# fat32_scan 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/storage/run_fat32_scan.do
# ================================================================

vlib work
vlog ../src/storage/fat32_scan.v ../sim_tb/storage/tb_fat32_scan.v
vsim tb_fat32_scan
run -all
quit -f
