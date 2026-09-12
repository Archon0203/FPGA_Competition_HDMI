if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog -work work ../src/framebuf/line_buffer_pingpong.v
vlog -work work ../src/display/hdmi_framebuffer_scanout.v
vlog -work work ../sim_tb/display/tb_hdmi_framebuffer_scanout.v
vsim -c work.tb_hdmi_framebuffer_scanout
run -all
quit -f
