# ================================================================
# fat32_file_reader 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/storage/run_fat32_file_reader.do
# ================================================================

vlib work
vlog ../src/storage/fat32_file_reader.v ../sim_tb/storage/tb_fat32_file_reader.v
vsim tb_fat32_file_reader
run -all
quit -f
