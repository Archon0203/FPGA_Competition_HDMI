# frame_buffer_manager P0-04 [U] unit regression
# Run from sim_work:
#   vsim -c -do ../sim_tb/framebuf/run_frame_buffer_manager.do

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog ../src/framebuf/frame_buffer_manager.v ../sim_tb/framebuf/tb_frame_buffer_manager.v
vsim -c tb_frame_buffer_manager
run -all
quit -f
