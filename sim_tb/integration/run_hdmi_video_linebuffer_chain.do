transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog -work work ../src/framebuf/line_buffer_pingpong.v
vlog -work work ../src/display/hdmi_video_adapter.v
vlog -work work ../sim_tb/integration/tb_hdmi_video_linebuffer_chain.v
vsim -c work.tb_hdmi_video_linebuffer_chain
run -all
quit -f
