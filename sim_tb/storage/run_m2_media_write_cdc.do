onerror {quit -code 1 -force}
vlib work
vlog ../../src/framebuf/async_fifo.v ../../src/framebuf/m2_media_write_cdc.v tb_m2_media_write_cdc.v
vsim work.tb_m2_media_write_cdc
run -all
