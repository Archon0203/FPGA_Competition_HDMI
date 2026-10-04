if {[file exists work]} {vdel -lib work -all}
vlib work
vmap work work
vlog ../../src/dual_board/m2_open_dispatcher.v tb_m2_open_dispatcher.v
vsim -c work.tb_m2_open_dispatcher -do "run -all; quit -f"
