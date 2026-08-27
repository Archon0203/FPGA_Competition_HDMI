# ================================================================
# async_fifo 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/framebuf/run_async_fifo.do
# ================================================================

vlib work
vlog ../src/framebuf/async_fifo.v ../sim_tb/framebuf/tb_async_fifo.v
vsim tb_async_fifo
run -all
quit -f
