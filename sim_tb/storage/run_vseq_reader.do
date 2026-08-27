# ================================================================
# vseq_reader 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/storage/run_vseq_reader.do
# ================================================================

vlib work
vlog ../src/storage/vseq_reader.v ../sim_tb/storage/tb_vseq_reader.v
vsim tb_vseq_reader
run -all
quit -f
