# ================================================================
# tone_gen 仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/audio/run_tone_gen.do
# ================================================================

vlib work
vlog ../src/audio/tone_gen.v ../sim_tb/audio/tb_tone_gen.v
vsim tb_tone_gen
run -all
quit -f
