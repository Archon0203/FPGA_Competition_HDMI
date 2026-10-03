onerror {quit -code 1 -force}
vlib work
vlog ../../src/dual_board/m1b_line_packetizer.v ../../src/dual_board/m2_media_line_source.v ../../src/dual_board/m2_line_packet_tx.v ../../src/dual_board/m2_line_packet_rx.v ../../src/dual_board/m2_frame_commit.v
vlog tb_m2_abc_loop.v
vsim work.tb_m2_abc_loop
run -all
