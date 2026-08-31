# framebuffer_writer P0-03 [U] unit regression
# Run from sim_work:
#   vsim -c -do ../sim_tb/framebuf/run_framebuffer_writer.do

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog ../src/framebuf/framebuffer_writer.v ../sim_tb/framebuf/tb_framebuffer_writer.v
vsim -c tb_framebuffer_writer
run -all
quit -f
