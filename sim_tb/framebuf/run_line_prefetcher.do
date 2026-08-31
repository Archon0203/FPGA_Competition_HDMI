# line_prefetcher P0-06 [U] unit regression
# Run from sim_work:
#   vsim -c -do ../sim_tb/framebuf/run_line_prefetcher.do

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog ../src/framebuf/line_prefetcher.v ../sim_tb/framebuf/tb_line_prefetcher.v
vsim -c tb_line_prefetcher
run -all
quit -f
