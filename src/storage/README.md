# src/storage
- `sd_spi.v`：SD/TF 卡 SPI 模式控制器（扇区级读）。
- `sd_reader.v`：高层次读卡状态机（CMD/ACMD 协商、读超时/重试）。
- `fat32_scan.v`：分区表(MBR)/FAT/目录项解析，产出图片与视频文件索引表。
- `bmp_parser.v`：解析 BMP（14B 文件头 + 40B 信息头），支持 24 位非压缩。
- `vseq_reader.v`：解析自定义视频帧序列容器（`.vseq`），供流式播放。

