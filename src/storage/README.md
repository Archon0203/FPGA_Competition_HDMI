> P0 media chain 已冻结为 `[C] PASS(1698)`；当前状态权威统一见 `docs/03_plan_and_status.md`。

# src/storage
- `sd_spi.v` ✓：SPI Mode0 字节级主控制器（MSB 先发，上升沿采样）。
- `sd_reader.v` ✓：SD SPI 命令状态机（CMD0/CMD8/CMD55/ACMD41/CMD17，超时重试，512B 读）。
- `fat32_scan.v` ✓：FAT32 分区/BPB/根目录首簇扫描，建立文件索引（8.3 短名，BMP/SEQ）；可遍历根目录首簇内各扇区，尚未跟随根目录 FAT 链到后续簇。
- `bmp_parser.v` ✓：解析 BMP（14B 文件头 + 40B 信息头），支持 24 位非压缩，输出宽/高/bpp/像素偏移。
- `vseq_reader.v` ✅：解析自定义视频帧序列容器（`.vseq`，头+帧流）。
- `vseq_yuv_unpack.v` ✅：把 `.vseq` YUV444 字节流解包为逐像素 Y/Cb/Cr。

## M1A 从板媒体服务骨架

- `m1a_protocol.vh`、`m1a_spi_slave.v`、`m1a_command_decoder.v`：SPI Mode 0 字节接收及带 CRC-16/CCITT 的命令帧解码；每次 CS 事务传一字节，命令帧为 `SOF(0xA5), opcode, length, payload, CRC16`。
- `m1a_provider_cdc.v`：通过异步 FIFO 将 provider 字节流跨到 service 时钟域，提供 ready/valid 和 sticky overflow。
- `m1a_media_service_mock.v`：deterministic catalog、descriptor、credit/PLAY 状态和 ready/valid 行数据 mock。
- `m1a_service_shell.v`：连接 SPI ingress FIFO、命令解码、provider CDC 与 mock 服务；SPI RX FIFO 溢出可通过 `spi_rx_overflow` 观测，状态回传使用稳定数据 mailbox。
- `m1a_catalog_table.v`：独立的 scanner-entry 缓存与 descriptor 查询边界；仅成功 scan 发布 catalog，重扫立即使旧 epoch/catalog 失效。当前仅做接口级独立仿真。
- `m1a_fat32_catalog.v`：将现有 `fat32_scan` 与 `m1a_catalog_table` 接成 FAT32 目录查询路径；外部提供扇区字节流，模块扫描 MBR/BPB/根目录并返回文件 descriptor。尚未接入 TF/SPI 读卡器。

M1A 当前包含模块级/从板 shell 骨架、仿真 mock 和 FAT32 sector-stream catalog wrapper。它仍没有实现真实 TF/SPI provider，也没有定义线上 packet sequence/CRC、GPIO source-synchronous link 或主板 frame commit；这些边界由后续 A/B 集成契约确定。不要将模块级仿真视为双板或 P1-05B 完成证据。
