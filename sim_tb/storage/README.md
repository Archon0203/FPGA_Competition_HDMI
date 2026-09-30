> P0 media chain 已冻结为 `[C] PASS(1698)`；当前状态权威统一见 `docs/03_plan_and_status.md`。

# sim_tb/storage
SD 读卡 / FAT32 / BMP / `.vseq` 解析的 testbench。对应 `src/storage`：

```
tb_sd_spi.v       + run_sd_spi.do       # SPI 主控字节收发
tb_sd_reader.v    + run_sd_reader.do    # SD 命令初始化 + 读块
tb_fat32_scan.v   + run_fat32_scan.do   # MBR/BPB/根目录扫描
tb_bmp_parser.v   + run_bmp_parser.do   # 640x480 24bit BMP 头解析
tb_vseq_reader.v  + run_vseq_reader.do  # .vseq 头 + 帧流
tb_vseq_yuv_unpack.v + run_vseq_yuv_unpack.do  # YUV444 字节流 -> 像素
tb_m1a_*.v                                    # M1A SPI/decoder/CDC/mock/shell/catalog 回归
```

运行（在 `sim_work` 目录）：
```powershell
vsim -c -do ../sim_tb/storage/run_sd_reader.do
```

M1A 完整回归（QuestaSim 10.7c，PowerShell，从仓库根目录运行）：

```powershell
& .\sim_tb\storage\run_m1a.ps1
```

脚本单独编译 M1A 依赖，并逐个启动八个 testbench；每项必须输出 `PASS`，否则脚本以失败退出。测试覆盖 SPI 字节序、命令 CRC/长度、异步 FIFO 顺序与背压、媒体输出背压稳定性、shell 集成、catalog table、FAT32 MBR/BPB/多扇区根目录到 descriptor 的路径及既有 `fat32_scan` 回归。集成用例使用受控扇区流，不代表真实 TF/SPI provider 已完成。`run_m1a.do` 只运行 shell 集成用例；完整回归请使用上述脚本，避免 `$finish` 结束当前 Questa 会话后后续用例未执行。
