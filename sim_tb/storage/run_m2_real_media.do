transcript file transcript_m2_real_media.txt
vlib work
vlog -work work +incdir+../../src/storage ../../src/storage/fat32_scan.v ../../src/storage/m1a_catalog_table.v ../../src/storage/m1a_fat32_catalog.v
vlog -work work +incdir+../../src/storage ../../src/storage/fat32_file_reader.v ../../src/storage/bmp_parser.v ../../src/storage/bmp_pixel_stream.v
vlog -work work +incdir+../../src/storage ../../src/framebuf/framebuffer_writer.v ../../src/framebuf/p1_media_framebuffer_loader.v
vlog -work work +incdir+../../src/storage ../../src/storage/m2_real_media_service.v ../../src/storage/sd_spi.v ../../src/storage/m2_official_spi_master.v ../../src/storage/sd_reader.v ../../src/storage/m2_tf_sector_provider.v ../../src/storage/m2_slave_tf_media_core.v
vlog -work work +incdir+../../src/storage ../../src/dual_board/m1b_line_packetizer.v ../../src/dual_board/m2_line_packet_tx.v ../../src/dual_board/m2_frame_packet_source.v ../../src/dual_board/m2_line_packet_rx.v ../../src/framebuf/m2_master_frame_store.v ../../src/framebuf/m2_master_line_core.v
vlog -work work +incdir+../../src/storage tb_m2_real_media_service.v
vsim -c work.tb_m2_real_media_service
run -all
