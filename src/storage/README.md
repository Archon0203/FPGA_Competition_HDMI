# src/storage
- `sd_spi.v` ✓：SPI Mode0 字节级主控制器（MSB 先发，上升沿采样）。
- `sd_reader.v` ✓：SD SPI 命令状态机（CMD0/CMD8/CMD55/ACMD41/CMD17，超时重试，512B 读）。
- `fat32_scan.v` ✓：FAT32 分区/BPB/根目录扫描，建立文件索引（8.3 短名，BMP/SEQ）。
- `bmp_parser.v` ✓：解析 BMP（14B 文件头 + 40B 信息头），支持 24 位非压缩，输出宽/高/bpp/像素偏移。
- `vseq_reader.v` ✓：解析自定义视频帧序列容器（`.vseq`，头+帧流）。
