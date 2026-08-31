> P0 Freeze Status (2026-08-31): P0-01~07 [U], P0-08 [C-sub], P0-09 [C]; P0 media chain 已冻结。P0-09 ModelSim: checks=1698 PASS。P0 [C] 仅代表纯 RTL + mock SDRAM 端到端通过，不代表 APUG011/APUG092、TD synthesis/P&R 或上板通过。权威冻结记录见 docs/35_P0_IMPLEMENTATION_FREEZE.md。

# sim_tb/framebuf
SDRAM 控制 / 帧缓冲 / 异步 FIFO 的 testbench。对应 `src/framebuf`：

```
tb_async_fifo.v + run_async_fifo.do   # 已完成
```

运行（在 `sim_work` 目录）：
```powershell
vsim -c -do ../sim_tb/framebuf/run_async_fifo.do
```
