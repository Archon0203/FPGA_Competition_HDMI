# ================================================================
# vga_timing simulation batch script.
# Run from the sim_tb directory:
#   vsim -c -do ../sim/run_vga_timing.do
# This compiles the RTL + testbench into sim_tb/work and simulates.
# ================================================================

vlib work
vlog ../src/top/vga_timing.v ../sim/tb_vga_timing.v
vsim tb_vga_timing
run -all
quit -f

