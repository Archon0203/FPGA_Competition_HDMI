# framebuf

P0/P1 framebuffer 与 SDRAM abstraction。

## 稳定模块

- `async_fifo.v`：双时钟 FIFO；
- `frame_buffer_manager.v`：A/B framebuffer metadata/swap；
- `framebuffer_writer.v`：RGB888 → abstract write requests；
- `line_prefetcher.v`：ordered line prefetch；
- `line_buffer_pingpong.v`：双行 ping-pong buffer；
- `sdram_arbiter.v`：read-priority arbiter；
- `sdram_adapter.v`：P1-02 frozen random/single-word adapter。

## P1-05A stable additions

### `p1_framebuffer_pattern_writer.v`

150 MHz 固定 framebuffer 初始化器。`[U] PASS(259)`。

### `p1_sdram_read_cdc_bridge.v`

25 MHz request ↔ 150 MHz response ordered CDC。`[U] PASS(13)`。

### `p1_sdram_hdmi_pipeline.v`

组织 CDC、prefetch、ping-pong line buffer、scanout。`[C-sub] PASS(258)`。

### `p1_sdram_cached_adapter.v`

P1-05 sequential-video adapter；P1-02 `sdram_adapter.v` 不改。

读取：4-word group cache，顺序读取最终 unit `PASS(58)`，`abstract_reads=8 / app_reads=8 / hits=6 / misses=2`。

写入：one-entry registered request slice；握手后 APUG011 transaction 只依赖内部 addr/data 寄存器。该结构是最终 150 MHz timing closure 的关键修复。

完整 cached provider chain：`PASS(260), pixels=256, underflow=0`；official APUG011 compatibility：`PASS(24)`。

## P1-05B candidate additions

### `p1_media_framebuffer_loader.v`

P1-05B 写入侧封装：`FAT32 file reader -> BMP parser/pixel stream -> framebuffer_writer -> abstract mem_wr`。该模块复用 P0 已冻结的媒体契约，默认只接受 640×480、24-bit BI_RGB bottom-up BMP，并保持 P1-05A HDMI/read/display path 不变。

该模块当前为 `[U] PASS`；对应 provider-realistic ModelSim 入口为：

```text
sim_tb/integration/run_p1_media_framebuffer_loader.do
```

回归覆盖 fragmented FAT32、BMP BGR/bottom-up/padding、非法 signature 拒绝，以及 `sdram_arbiter -> p1_sdram_cached_adapter -> mock APUG011`；结果为 `PASS(225)`。真实 TF physical reader 与该 150 MHz write-domain loader 之间仍必须使用显式 CDC/provider wrapper，不能直接跨域连接。

## Current TD6.2.1 timing note

TD6.2.1 final routed STA（2026-09-21）：0 setup / 0 hold，SWNS `+0.599 ns`、HWNS `+0.003 ns`，coverage `99.17%`。硬件最小裕量仅 3 ps，任何后续改动必须重新 P&R/STA。当前 run 仍有两个 SDRAM location warning 和一条 local clock routing warning。

## 规则

- SDRAM word 固定 `0x00RRGGBB`；
- 跨时钟数据必须显式 CDC；
- active line 必须连续；
- 修改 frozen module 后必须重跑对应 regression；
- P1-05 不修改 APUG011 protected source。
