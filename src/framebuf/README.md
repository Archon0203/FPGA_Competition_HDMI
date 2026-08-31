> P0 Freeze Status (2026-08-31): P0-01~07 [U], P0-08 [C-sub], P0-09 [C]; P0 media chain 已冻结。P0-09 ModelSim: checks=1698 PASS。P0 [C] 仅代表纯 RTL + mock SDRAM 端到端通过，不代表 APUG011/APUG092、TD synthesis/P&R 或上板通过。权威冻结记录见 docs/35_P0_IMPLEMENTATION_FREEZE.md。

# src/framebuf
- `async_fifo.v` ✓：参数化跨时钟域异步 FIFO（格雷码指针 CDC，full/empty 由同步指针比较）。
- `sdram_ctrl.v`：SDRAM 控制器（命令/自动刷新/行预充电/读写仲裁），建议复用官方 IP/参考。
- `frame_buffer.v`：帧缓冲管理，图像双缓冲 + 视频三缓冲（ping-pong），地址映射。
