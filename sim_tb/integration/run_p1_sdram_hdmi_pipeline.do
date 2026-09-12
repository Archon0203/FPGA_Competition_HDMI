if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog -work work ../src/framebuf/async_fifo.v
vlog -work work ../src/framebuf/p1_sdram_read_cdc_bridge.v
vlog -work work ../src/framebuf/line_prefetcher.v
vlog -work work ../src/framebuf/line_buffer_pingpong.v
vlog -work work ../src/display/hdmi_framebuffer_scanout.v
vlog -work work ../src/framebuf/p1_sdram_hdmi_pipeline.v
vlog -work work ../sim_tb/integration/tb_p1_sdram_hdmi_pipeline.v
vsim -c work.tb_p1_sdram_hdmi_pipeline
run -all
quit -f
