onerror {quit -code 1 -force}
vlib work
vlog ../../src/storage/sd_spi.v tb_sd_spi.v
vsim -gMODE3=1 work.tb_sd_spi
run -all
