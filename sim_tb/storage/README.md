> P0 Freeze Status (2026-08-31): P0-01~07 [U], P0-08 [C-sub], P0-09 [C]; P0 media chain 已冻结。P0-09 ModelSim: checks=1698 PASS。P0 [C] 仅代表纯 RTL + mock SDRAM 端到端通过，不代表 APUG011/APUG092、TD synthesis/P&R 或上板通过。权威冻结记录见 docs/35_P0_IMPLEMENTATION_FREEZE.md。

# sim_tb/storage
SD 读卡 / FAT32 / BMP / `.vseq` 解析的 testbench。对应 `src/storage`：

```
tb_sd_spi.v       + run_sd_spi.do       # SPI 主控字节收发
tb_sd_reader.v    + run_sd_reader.do    # SD 命令初始化 + 读块
tb_fat32_scan.v   + run_fat32_scan.do   # MBR/BPB/根目录扫描
tb_bmp_parser.v   + run_bmp_parser.do   # 640x480 24bit BMP 头解析
tb_vseq_reader.v  + run_vseq_reader.do  # .vseq 头 + 帧流
tb_vseq_yuv_unpack.v + run_vseq_yuv_unpack.do  # YUV444 字节流 -> 像素
```

运行（在 `sim_work` 目录）：
```powershell
vsim -c -do ../sim_tb/storage/run_sd_reader.do
```
