# sdram_arbiter P0-07 candidate unit simulation
# Run from sim_work:
#   vsim -c -do ../sim_tb/framebuf/run_sdram_arbiter.do

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog ../src/framebuf/sdram_arbiter.v ../sim_tb/framebuf/tb_sdram_arbiter.v
vsim -c tb_sdram_arbiter
run -all
quit -f
