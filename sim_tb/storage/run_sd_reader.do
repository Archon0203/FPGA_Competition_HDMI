# ================================================================
# sd_reader 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/storage/run_sd_reader.do
# ================================================================

vlib work
vlog ../src/storage/sd_reader.v ../sim_tb/storage/tb_sd_reader.v
vsim tb_sd_reader
run -all
quit -f
