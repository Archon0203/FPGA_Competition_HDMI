transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

set APUG092 ../src/vendor/anlogic/apug092

# Protected-core behavioral integration stops before hdmi_phy_wrapper so no
# EG_LOGIC_ODDR simulation model is required here.
vlog -work work $APUG092/hdmi_1_4b_transmitter_core_wrapper.enc.v
vlog -work work ../src/display/hdmi_test_pattern_line_provider.v
vlog -work work ../src/display/hdmi_video_adapter.v
vlog -work work ../src/top/apug092_core_wrapper.v
vlog -work work ../sim_tb/integration/tb_apug092_external_video_core.v

vsim -t ps -voptargs=+acc +notimingchecks work.tb_apug092_external_video_core
run -all
quit -f
