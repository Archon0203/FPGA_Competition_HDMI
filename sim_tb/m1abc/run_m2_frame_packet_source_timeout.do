onerror {quit -code 1 -force}
vlib work
vlog ../../src/dual_board/m1b_line_packetizer.v ../../src/dual_board/m2_line_packet_tx.v ../../src/dual_board/m2_frame_packet_source.v
vlog tb_m2_frame_packet_source_timeout.v
vsim work.tb_m2_frame_packet_source_timeout
run -all
