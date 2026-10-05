onerror {quit -code 1 -force}
transcript file transcript_m2_real_media_remote_link.txt
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -work work +incdir+../../src/storage \
  ../../src/storage/fat32_scan.v ../../src/storage/m1a_catalog_table.v \
  ../../src/storage/m1a_fat32_catalog.v ../../src/storage/fat32_file_reader.v \
  ../../src/storage/bmp_parser.v ../../src/storage/bmp_pixel_stream.v \
  ../../src/framebuf/framebuffer_writer.v ../../src/framebuf/p1_media_framebuffer_loader.v \
  ../../src/storage/m2_real_media_service.v
vlog -work work ../../src/dual_board/m2_remote_frame.v \
  ../../src/dual_board/m2_gpio_mailbox.v \
  tb_m2_real_media_remote_link.v
vsim -c work.tb_m2_real_media_remote_link
run -all
