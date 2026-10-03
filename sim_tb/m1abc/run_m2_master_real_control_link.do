transcript file transcript_m2_master_real_control_link.txt
if {[file exists work]} {vdel -lib work -all}
vlib work
vmap work work
vlog +incdir+../../src/storage ../../src/dual_board/db_startup_reset.v
vlog +incdir+../../src/storage ../../src/dual_board/db_uart_tx.v
vlog +incdir+../../src/storage ../../src/dual_board/db_uart_rx.v
vlog +incdir+../../src/storage ../../src/dual_board/db_ctrl_frame_tx.v
vlog +incdir+../../src/storage ../../src/dual_board/db_ctrl_frame_parser.v
vlog +incdir+../../src/storage ../../src/interact/key_filter.v
vlog +incdir+../../src/storage ../../src/app/media_command_controller.v
vlog +incdir+../../src/storage ../../src/app/m1c_coordinator_uart.v
vlog +incdir+../../src/storage ../../src/dual_board/m2_media_line_source.v
vlog +incdir+../../src/storage ../../src/dual_board/m2_line_packet_tx.v
vlog +incdir+../../src/storage ../../src/dual_board/m2_line_packet_rx.v
vlog +incdir+../../src/storage ../../src/dual_board/m2_frame_commit.v
vlog +incdir+../../src/storage ../../src/dual_board/m2_abc_loopback_diag.v
vlog +incdir+../../src/storage ../../src/dual_board/m1b_prbs31.v
vlog +incdir+../../src/storage ../../src/dual_board/m1b_line_packetizer.v
vlog +incdir+../../src/storage ../../src/dual_board/m1b_line_packet_checker.v
vlog +incdir+../../src/storage ../../src/dual_board/m1b_packet_selftest.v
vlog +incdir+../../src/storage ../../src/dual_board/m2_real_media_uart_bridge.v
vlog +incdir+../../src/storage ../../src/top/m1abc_master_control_top.v
vlog +incdir+../../src/storage tb_m2_master_real_control_link.v
vsim -c work.tb_m2_master_real_control_link -do "run -all; quit -f"
