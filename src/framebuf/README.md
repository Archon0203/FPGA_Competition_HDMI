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

## P1-05A final timing note

combined STA：0 setup / 0 hold，WNS `+0.068 ns`。该余量较薄，后续改动必须重新 STA。

## 规则

- SDRAM word 固定 `0x00RRGGBB`；
- 跨时钟数据必须显式 CDC；
- active line 必须连续；
- 修改 frozen module 后必须重跑对应 regression；
- P1-05 不修改 APUG011 protected source。
