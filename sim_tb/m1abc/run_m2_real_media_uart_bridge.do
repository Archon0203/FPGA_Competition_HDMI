transcript on
if {[file exists work]} {vdel -lib work -all}
vlib work
vmap work work
vlog +incdir+../../src/storage ../../src/dual_board/m2_real_media_uart_bridge.v tb_m2_real_media_uart_bridge.v
vsim -c work.tb_m2_real_media_uart_bridge -do "run -all; quit -f"
