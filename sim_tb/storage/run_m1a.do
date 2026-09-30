# Run from sim_work: vsim -c -do ../sim_tb/storage/run_m1a.do
# The full 5-test regression is run_m1a.ps1; each testbench uses $finish,
# which ends this Questa session, so a .do file cannot safely chain them.
vlog +incdir+../src/storage ../src/framebuf/async_fifo.v ../src/storage/m1a_spi_slave.v ../src/storage/m1a_command_decoder.v ../src/storage/m1a_provider_cdc.v ../src/storage/m1a_media_service_mock.v ../src/storage/m1a_service_shell.v ../sim_tb/storage/tb_m1a_service_shell.v
vsim tb_m1a_service_shell
run -all
