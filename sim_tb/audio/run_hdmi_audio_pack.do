# ================================================================
# hdmi_audio_pack 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/audio/run_hdmi_audio_pack.do
# ================================================================

vlib work
vlog ../src/audio/hdmi_audio_pack.v ../sim_tb/audio/tb_hdmi_audio_pack.v
vsim tb_hdmi_audio_pack
run -all
quit -f
