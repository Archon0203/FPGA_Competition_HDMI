if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work
vlog -work work ../src/framebuf/p1_sdram_cached_adapter.v
vlog -work work ../sim_tb/framebuf/mock_apug011_app_port.v
vlog -work work ../sim_tb/framebuf/tb_p1_sdram_cached_adapter.v
vsim -c work.tb_p1_sdram_cached_adapter
run -all
quit -f
