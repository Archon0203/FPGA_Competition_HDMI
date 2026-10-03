onerror {quit -code 1 -force}
vlib work
vlog +incdir+../../src/storage ../../src/storage/sd_spi.v ../../src/storage/m2_official_spi_master.v ../../src/storage/sd_reader.v ../../src/storage/m2_tf_sector_provider.v
vlog +incdir+../../src/storage ../../src/storage/fat32_scan.v ../../src/storage/m1a_catalog_table.v ../../src/storage/m1a_fat32_catalog.v
vlog +incdir+../../src/storage ../../src/storage/fat32_file_reader.v ../../src/storage/bmp_parser.v ../../src/storage/bmp_pixel_stream.v
vlog +incdir+../../src/storage ../../src/framebuf/framebuffer_writer.v ../../src/framebuf/p1_media_framebuffer_loader.v ../../src/storage/m2_real_media_service.v ../../src/storage/m2_slave_tf_media_core.v
vlog tb_m2_card_spi_snapshot.v
vsim work.tb_m2_card_spi_snapshot +CARD_IMAGE=$env(CARD_IMAGE)
run -all
