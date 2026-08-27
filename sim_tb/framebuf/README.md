# sim_tb/framebuf
SDRAM 控制 / 帧缓冲 / 异步 FIFO 的 testbench。对应 `src/framebuf`：

```
tb_async_fifo.v + run_async_fifo.do   # 已完成
```

运行（在 `sim_work` 目录）：
```powershell
vsim -c -do ../sim_tb/framebuf/run_async_fifo.do
```
