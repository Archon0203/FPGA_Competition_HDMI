# P1-05B write-side provider-realistic regression.
# Run from sim_work:
#   E:/modelsim64_10.6d/win64/vsim -c -do ../sim_tb/integration/run_p1_media_framebuffer_loader.do

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -work work ../src/storage/fat32_file_reader.v
vlog -work work ../src/storage/bmp_parser.v
vlog -work work ../src/storage/bmp_pixel_stream.v
vlog -work work ../src/framebuf/framebuffer_writer.v
vlog -work work ../src/framebuf/p1_media_framebuffer_loader.v
vlog -work work ../src/framebuf/sdram_arbiter.v
vlog -work work ../src/framebuf/p1_sdram_cached_adapter.v
vlog -work work ../sim_tb/framebuf/mock_apug011_app_port.v
vlog -work work ../sim_tb/integration/tb_p1_media_framebuffer_loader.v

vsim -c work.tb_p1_media_framebuffer_loader
run -all
quit -f
