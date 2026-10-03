onerror {quit -code 1 -force}
vlib work
vlog +incdir+../../src/storage ../../src/storage/fat32_scan.v ../../src/storage/m1a_catalog_table.v ../../src/storage/m1a_fat32_catalog.v
vlog +incdir+../../src/storage ../../src/storage/fat32_file_reader.v ../../src/storage/bmp_parser.v ../../src/storage/bmp_pixel_stream.v
vlog +incdir+../../src/storage ../../src/framebuf/framebuffer_writer.v ../../src/framebuf/p1_media_framebuffer_loader.v ../../src/storage/m2_real_media_service.v
vlog tb_m2_card_snapshot.v
if {[info exists env(CORRUPT_HEADER)] && $env(CORRUPT_HEADER) eq "1"} {
    vsim work.tb_m2_card_snapshot +CARD_IMAGE=$env(CARD_IMAGE) +CORRUPT_HEADER
} elseif {[info exists env(DROP_FLOW_CONTROL)] && $env(DROP_FLOW_CONTROL) eq "1"} {
    vsim work.tb_m2_card_snapshot +CARD_IMAGE=$env(CARD_IMAGE) +STALL_WRITES +DROP_FLOW_CONTROL
} else {
    vsim work.tb_m2_card_snapshot +CARD_IMAGE=$env(CARD_IMAGE) +STALL_WRITES
}
run -all
