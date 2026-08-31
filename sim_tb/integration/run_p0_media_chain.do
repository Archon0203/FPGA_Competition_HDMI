# P0 final media-chain end-to-end candidate
# Run from sim_work:
#   vsim -c -do ../sim_tb/integration/run_p0_media_chain.do

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog \
  ../src/storage/fat32_file_reader.v \
  ../src/storage/bmp_parser.v \
  ../src/storage/bmp_pixel_stream.v \
  ../src/framebuf/framebuffer_writer.v \
  ../src/framebuf/frame_buffer_manager.v \
  ../src/framebuf/sdram_arbiter.v \
  ../src/framebuf/line_prefetcher.v \
  ../src/framebuf/line_buffer_pingpong.v \
  ../sim_tb/framebuf/mock_sdram.v \
  ../sim_tb/integration/tb_p0_media_chain.v

vsim -c tb_p0_media_chain
run -all
quit -f
