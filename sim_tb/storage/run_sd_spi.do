# ================================================================
# sd_spi 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/storage/run_sd_spi.do
# ================================================================

vlib work
vlog ../src/storage/sd_spi.v ../sim_tb/storage/tb_sd_spi.v
vsim tb_sd_spi
run -all
quit -f
