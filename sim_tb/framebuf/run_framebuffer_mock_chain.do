# P0-08 framebuffer/mock-SDRAM [C-sub] integration regression
# Run from sim_work:
#   vsim -c -do ../sim_tb/framebuf/run_framebuffer_mock_chain.do

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog \
  ../src/framebuf/frame_buffer_manager.v \
  ../src/framebuf/framebuffer_writer.v \
  ../src/framebuf/sdram_arbiter.v \
  ../src/framebuf/line_prefetcher.v \
  ../src/framebuf/line_buffer_pingpong.v \
  ../sim_tb/framebuf/mock_sdram.v \
  ../sim_tb/framebuf/tb_framebuffer_mock_chain.v
vsim -c tb_framebuffer_mock_chain
run -all
quit -f
