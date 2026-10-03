onerror {quit -code 1 -force}
vlib work
vlog ../../src/storage/fat32_scan.v tb_fat32_scan.v
vsim -gSUPERFLOPPY=1 work.tb_fat32_scan
run -all
