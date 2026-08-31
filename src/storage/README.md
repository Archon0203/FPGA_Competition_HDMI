# src/storage

完成状态采用 `[U]/[C]/[S]/[B]/[L]` 口径；本目录当前只记录单模块成熟度，不代表媒体主链已经 `[C]`。

- `sd_spi.v` [U]：SPI Mode0 字节级主控制器（MSB 先发，上升沿采样）。
- `sd_reader.v` [U]：SDHC/SDXC SPI 初始化与 CMD17 单块读取；真卡仍需 `[B]`。
- `fat32_scan.v` [U]：FAT32 MBR/BPB/根目录第一 sector 索引，8.3 短名；不负责完整文件流。
- `fat32_file_reader.v` [U]：P0-01；cluster→LBA、fragmented FAT chain、连续文件 byte stream、`file_size` 截止；CASE0~CASE8 adversarial PASS（checks=18）。
- `bmp_parser.v` [U]：解析 24 位 BI_RGB BMP 文件头/信息头，输出宽高/bpp/像素偏移。
- `bmp_pixel_stream.v` [U]：P0-02；BGR→RGB、bottom-up、padding、x/y/pixel_valid；CASE0~CASE13 adversarial PASS（checks=13393）。
- `vseq_reader.v` [U]：解析自定义 `.vseq` 容器（头 + 帧流）。
- `vseq_yuv_unpack.v` [U]：YUV444 字节流 → 逐像素 Y/Cb/Cr。

`fat32_file_reader` 详细接口/向量：`../../docs/13_fat32_file_reader_interface.md`、`../../docs/14_fat32_file_reader_test_vectors.md`。
`bmp_pixel_stream` 详细接口/向量：`../../docs/15_bmp_pixel_stream_interface.md`、`../../docs/16_bmp_pixel_stream_test_vectors.md`。
