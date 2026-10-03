onerror {quit -code 1 -force}
vlib work
vlog ../../src/framebuf/async_fifo.v ../../src/dual_board/m2_gpio7_word_tx.v ../../src/dual_board/m2_gpio7_word_rx.v tb_m2_gpio7_word_phy.v
vsim work.tb_m2_gpio7_word_phy
run -all
