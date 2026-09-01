quit -sim
if {[file exists work]} {vdel -lib work -all}
vlib work
vmap work work
vlog ../src/top/p1_apug011_bist.v
vlog ../sim_tb/top/tb_p1_apug011_bist.v
vsim -c -voptargs=+acc work.tb_p1_apug011_bist
run -all
quit -f
