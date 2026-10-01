transcript on
onerror {puts "FATAL: Questa command failed"; quit -code 1 -force}

if {[file exists work]} {
    catch {vdel -lib work -all}
    catch {file delete -force work}
}
vlib work
vmap work work

# Compile one source per command for QuestaSim 10.7c compatibility.
vlog -work work +incdir+../../src/storage ../../src/framebuf/async_fifo.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/db_startup_reset.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/db_uart_tx.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/db_uart_rx.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/db_ctrl_frame_tx.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/db_ctrl_frame_parser.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/m1b_prbs31.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/m1b_line_packetizer.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/m1b_line_packet_checker.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/m1b_packet_selftest.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/m1b_spi_master_byte.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/m1b_prbs_packet_tx.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/m1b_prbs_packet_rx.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/m1b_link_word_cdc.v
vlog -work work +incdir+../../src/storage ../../src/storage/m1a_spi_slave.v
vlog -work work +incdir+../../src/storage ../../src/storage/m1a_media_service_mock.v
vlog -work work +incdir+../../src/storage ../../src/storage/m1a_uart_service_bridge.v
vlog -work work +incdir+../../src/storage ../../src/interact/key_filter.v
vlog -work work +incdir+../../src/storage ../../src/app/media_command_controller.v
vlog -work work +incdir+../../src/storage ../../src/app/m1c_coordinator_uart.v
vlog -work work +incdir+../../src/storage ../../src/app/m1c_frame_config_cdc.v
vlog -work work +incdir+../../src/storage ../../src/display/hdmi_1080p_raster.v
vlog -work work +incdir+../../src/storage ../../src/top/m1abc_master_control_top.v
vlog -work work +incdir+../../src/storage ../../src/top/m1abc_slave_control_core.v

vlog -work work +incdir+../../src/storage tb_m1b_spi_byte_loop.v
vlog -work work +incdir+../../src/storage tb_m1b_prbs_link.v
vlog -work work +incdir+../../src/storage tb_m1b_link_word_cdc.v
vlog -work work +incdir+../../src/storage tb_m1b_packet_selftest.v
vlog -work work +incdir+../../src/storage tb_m1c_frame_config_cdc.v
vlog -work work +incdir+../../src/storage tb_hdmi_1080p_raster.v
vlog -work work +incdir+../../src/storage tb_m1abc_control_link.v

proc run_tb {name} {
    puts "===== RUN $name ====="
    vsim -voptargs="+acc" work.$name
    run -all
    quit -sim
}

run_tb tb_m1b_spi_byte_loop
run_tb tb_m1b_prbs_link
run_tb tb_m1b_link_word_cdc
run_tb tb_m1b_packet_selftest
run_tb tb_m1c_frame_config_cdc
run_tb tb_hdmi_1080p_raster
run_tb tb_m1abc_control_link

puts "ALL M1 ABC REGRESSIONS COMPLETED"
quit -code 0 -force
