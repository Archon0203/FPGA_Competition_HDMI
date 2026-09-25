# Run from sim_work:
#   vsim -c -do ../sim_tb/app/run_media_command_controller.do

vlib work
vlog ../src/app/media_command_controller.v ../sim_tb/app/tb_media_command_controller.v
vsim tb_media_command_controller
run -all
quit -f
