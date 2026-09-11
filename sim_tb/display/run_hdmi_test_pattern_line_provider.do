transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog -work work ../src/display/hdmi_test_pattern_line_provider.v
vlog -work work ../sim_tb/display/tb_hdmi_test_pattern_line_provider.v
vsim -c work.tb_hdmi_test_pattern_line_provider
run -all
quit -f
