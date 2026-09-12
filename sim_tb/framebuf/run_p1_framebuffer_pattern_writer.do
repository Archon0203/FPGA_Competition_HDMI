if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog -work work ../src/framebuf/p1_framebuffer_pattern_writer.v
vlog -work work ../sim_tb/framebuf/tb_p1_framebuffer_pattern_writer.v
vsim -c work.tb_p1_framebuffer_pattern_writer
run -all
quit -f
