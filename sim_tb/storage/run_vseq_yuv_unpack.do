# ================================================================
# vseq_yuv_unpack 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/storage/run_vseq_yuv_unpack.do
# ================================================================

vlib work
vlog ../src/storage/vseq_yuv_unpack.v ../sim_tb/storage/tb_vseq_yuv_unpack.v
vsim tb_vseq_yuv_unpack
run -all
quit -f
