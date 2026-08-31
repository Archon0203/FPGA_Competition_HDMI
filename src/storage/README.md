> P0 Freeze Status (2026-08-31): P0-01~07 [U], P0-08 [C-sub], P0-09 [C]; P0 media chain 已冻结。P0-09 ModelSim: checks=1698 PASS。P0 [C] 仅代表纯 RTL + mock SDRAM 端到端通过，不代表 APUG011/APUG092、TD synthesis/P&R 或上板通过。权威冻结记录见 docs/35_P0_IMPLEMENTATION_FREEZE.md。

# src/storage
- `sd_spi.v` ✓：SPI Mode0 字节级主控制器（MSB 先发，上升沿采样）。
- `sd_reader.v` ✓：SD SPI 命令状态机（CMD0/CMD8/CMD55/ACMD41/CMD17，超时重试，512B 读）。
- `fat32_scan.v` ✓：FAT32 分区/BPB/根目录扫描，建立文件索引（8.3 短名，BMP/SEQ）。
- `bmp_parser.v` ✓：解析 BMP（14B 文件头 + 40B 信息头），支持 24 位非压缩，输出宽/高/bpp/像素偏移。
- `vseq_reader.v` ✅：解析自定义视频帧序列容器（`.vseq`，头+帧流）。
- `vseq_yuv_unpack.v` ✅：把 `.vseq` YUV444 字节流解包为逐像素 Y/Cb/Cr。
