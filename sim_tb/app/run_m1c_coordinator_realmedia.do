if {[file exists work]} {vdel -lib work -all}
vlib work
vmap work work
vlog ../../src/app/m1c_coordinator_uart.v tb_m1c_coordinator_realmedia.v
vsim -c work.tb_m1c_coordinator_realmedia -do "run -all; quit -f"
