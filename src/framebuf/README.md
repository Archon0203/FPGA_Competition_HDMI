# src/framebuf

完成状态采用 `[U]/[C]/[S]/[B]/[L]`。Architecture Contract v1.0 下，业务模块只产生抽象内存请求；正式 SDRAM controller 使用 APUG011。

- `async_fifo.v` **[U]**：参数化跨时钟域 FIFO（注册 Gray pointer + 2FF CDC）。
- `framebuffer_writer.v` **[U]**：P0-03；CASE0~CASE8 PASS（checks=1345），RGB/x/y → word address + `0x00RRGGBB` write request。
- `frame_buffer_manager.v` **[U]**：P0-04；CASE0~CASE6 PASS（checks=166），Image A/B 双缓冲所有权、frame-boundary swap、读写保护。
- `line_buffer_pingpong.v` **[U]**：P0-05；CASE-GOLDEN+CASE0~CASE8 PASS（checks=2204）；24-bit RGB 保真、双行 bank、完整行 commit、连续输出、black-line underflow fallback。
- `line_prefetcher.v` **[U]**：P0-06；CASE0~CASE13 PASS（checks=2713）；frame line→连续 memory read，最多 8 outstanding，有序 response→line buffer，含 stale-response quarantine。
- `sdram_arbiter.v` **[U]**：P0-07；writer/prefetcher strict read-priority 仲裁、read/write 互斥、outstanding response guard。
- `sdram_adapter.v` ❌：P1；适配官方 APUG011 `sdr_as_ram`。

交付文档：

- P0-03/P0-04 `[U]`：`../../docs/17~20`
- P0-05/P0-06 `[U]`：`../../docs/21~24`
- P0-07 `[U]`：`../../docs/27~28`
- P0-08 mock framebuffer integration：`../../docs/29~30`

> 当前 P0-01~P0-06 均达到单元 `[U]`。P0-07/P0-08 未实际 ModelSim PASS 前不得升级状态；即使 P0-08 sub-chain PASS，仍需 FAT32/BMP 端到端 golden 回归后才可把完整 media chain 标 `[C]`。
