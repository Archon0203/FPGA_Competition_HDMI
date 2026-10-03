onerror {quit -code 1 -force}
vlib work
vlog ../../src/dual_board/m1b_line_packetizer.v ../../src/dual_board/m2_media_line_source.v ../../src/dual_board/m2_line_packet_tx.v ../../src/dual_board/m2_line_packet_rx.v ../../src/framebuf/m2_master_frame_store.v ../../src/framebuf/m2_master_line_core.v
vlog tb_m2_master_line_core.v
vsim work.tb_m2_master_line_core
run -all
