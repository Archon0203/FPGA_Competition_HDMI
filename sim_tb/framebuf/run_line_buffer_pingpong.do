# line_buffer_pingpong P0-05 [U] unit regression
# Run from sim_work:
#   vsim -c -do ../sim_tb/framebuf/run_line_buffer_pingpong.do

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog ../src/framebuf/line_buffer_pingpong.v ../sim_tb/framebuf/tb_line_buffer_pingpong.v
vsim -c tb_line_buffer_pingpong
run -all
quit -f
