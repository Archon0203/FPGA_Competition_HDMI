# sim_tb/storage

SD 读卡 / FAT32 / BMP / `.vseq` 相关 testbench。对应 `src/storage`：

```text
tb_sd_spi.v            + run_sd_spi.do            # SPI 主控字节收发
tb_sd_reader.v         + run_sd_reader.do         # SDHC/SDXC 初始化 + CMD17
tb_fat32_scan.v        + run_fat32_scan.do        # MBR/BPB/根目录第一 sector 索引
tb_fat32_file_reader.v + run_fat32_file_reader.do # fragmented FAT chain -> file byte stream
tb_bmp_parser.v        + run_bmp_parser.do        # 24bit BI_RGB BMP header
tb_bmp_pixel_stream.v + run_bmp_pixel_stream.do # BGR/padding/bottom-up pixel stream
tb_vseq_reader.v       + run_vseq_reader.do       # .vseq 头 + 帧流
tb_vseq_yuv_unpack.v   + run_vseq_yuv_unpack.do   # YUV444 byte stream -> pixel
```

运行（在 `sim_work` 目录）：

```powershell
vsim -c -do ../sim_tb/storage/run_fat32_file_reader.do
```

## P0-01 回归记录

2026-08-31，`tb_fat32_file_reader` 实际 ModelSim：CASE0~CASE8 全部执行，最终：

```text
PASS: fat32_file_reader all adversarial cases passed (checks=18)
```

因此 `fat32_file_reader` 标记为 `[U]`。这不代表 FAT32→BMP→framebuffer 媒体链达到 `[C]`。


## P0-02 回归记录

2026-08-31，`tb_bmp_pixel_stream` 实际 ModelSim：CASE0~CASE13 全部 PASS，最终：

```text
PASS: bmp_pixel_stream all adversarial cases passed (checks=13393)
```

波形抽查 CASE0 首像素：`R=0x21, G=0x45, B=0x62, x=0, y=1`，与独立 pattern golden 一致；因此 BGR→RGB、bottom-up 映射及 header_done/首像素同拍边界均通过。模块标记 `[U]`，但媒体链仍未 `[C]`。
