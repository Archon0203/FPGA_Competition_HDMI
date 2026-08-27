# src/framebuf
- `async_fifo.v` ✓：参数化跨时钟域异步 FIFO（格雷码指针 CDC，full/empty 由同步指针比较）。
- `sdram_ctrl.v`：SDRAM 控制器（命令/自动刷新/行预充电/读写仲裁），建议复用官方 IP/参考。
- `frame_buffer.v`：帧缓冲管理，图像双缓冲 + 视频三缓冲（ping-pong），地址映射。
