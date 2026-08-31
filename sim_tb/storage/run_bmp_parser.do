# ================================================================
# bmp_parser 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/storage/run_bmp_parser.do
# ================================================================

vlib work
vlog ../src/storage/bmp_parser.v ../sim_tb/storage/tb_bmp_parser.v
vsim tb_bmp_parser
run -all
quit -f
