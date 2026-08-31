# ================================================================
# audio_visual 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/audio/run_audio_visual.do
# ================================================================

vlib work
vlog ../src/audio/audio_visual.v ../sim_tb/audio/tb_audio_visual.v
vsim tb_audio_visual
run -all
quit -f
