# ================================================================
# bmp_pixel_stream P0-02 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/storage/run_bmp_pixel_stream.do
# ================================================================

vlib work
vlog ../src/storage/bmp_parser.v ../src/storage/bmp_pixel_stream.v ../sim_tb/storage/tb_bmp_pixel_stream.v
vsim tb_bmp_pixel_stream
run -all
quit -f
