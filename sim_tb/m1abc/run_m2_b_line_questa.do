onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -work work +acc \
    ../../src/dual_board/m2_gpio_mailbox.v \
    ../../src/dual_board/m2_remote_frame.v \
    tb_m2_mailbox_reset_recovery.v \
    tb_m2_remote_frame_link.v \
    tb_m2_remote_frame_idle_resync.v
vsim -c -voptargs=+acc work.tb_m2_mailbox_reset_recovery
run -all
quit -sim
vsim -c -voptargs=+acc work.tb_m2_remote_frame_link
run -all
quit -sim
vsim -c -voptargs=+acc work.tb_m2_remote_frame_idle_resync
run -all
quit -code 0
