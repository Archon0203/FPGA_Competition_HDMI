transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog -work work ../src/display/hdmi_video_adapter.v
vlog -work work ../sim_tb/display/tb_hdmi_video_adapter.v
vsim -c work.tb_hdmi_video_adapter
run -all
quit -f
