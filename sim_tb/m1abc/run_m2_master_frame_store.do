onerror {quit -code 1 -force}
vlib work
vlog ../../src/framebuf/m2_master_frame_store.v tb_m2_master_frame_store.v
vsim work.tb_m2_master_frame_store
run -all
