if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog -work work ../src/framebuf/async_fifo.v
vlog -work work ../src/framebuf/p1_sdram_read_cdc_bridge.v
vlog -work work ../sim_tb/framebuf/tb_p1_sdram_read_cdc_bridge.v
vsim -c work.tb_p1_sdram_read_cdc_bridge
run -all
quit -f
