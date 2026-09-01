transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -work work ../src/framebuf/sdram_arbiter.v
vlog -work work ../src/framebuf/sdram_adapter.v
vlog -work work ../sim_tb/framebuf/mock_apug011_app_port.v
vlog -work work ../sim_tb/framebuf/tb_sdram_arbiter_adapter_chain.v

vsim -voptargs=+acc work.tb_sdram_arbiter_adapter_chain
run -all
quit -f
