# src — 设计代码（可综合 RTL）

模块按子系统分子目录。一个模块一个 `.v` 文件，文件名与模块名一致。

| 子目录 | 包含模块 |
|---|---|
| `top/` | `system_top.v`（业务）、`hx4s20c_top.v`（vendor/board）、`clk_gen.v`、`reset_gen.v` |
| `storage/` | `sd_spi.v`、`sd_reader.v`、`fat32_scan.v`、`fat32_file_reader.v`、`bmp_parser.v`、`bmp_pixel_stream.v`、`vseq_reader.v`、`vseq_yuv_unpack.v` |
| `framebuf/` | `frame_buffer_manager.v`、`framebuffer_writer.v`、`line_prefetcher.v`、`line_buffer_pingpong.v`、`sdram_arbiter.v`、`sdram_adapter.v`、`async_fifo.v` |
| `display/` | `vga_timing.v`、`hdmi_video_adapter.v`、`color_space.v`、`yuv420_upsample.v`、`image_enhance.v`、`image_scaler.v`、`transition.v`、`osd_overlay.v`、`tmds_encoder.v`(educational) |
| `audio/` | `hdmi_audio_adapter.v`、`tone_gen.v`、`audio_visual.v`、`hdmi_audio_pack.v`(educational) |
| `interact/` | `key_filter.v`、`sw_filter.v`、`menu_fsm.v`、`seg_driver.v`、`dual_led.v`、`beep.v` |
| `app/` | `app_scenario.v`（信息发布终端业务） |

约束：
- 每个 `.v` 顶部写 IEEE 风格头注释：作者 / 日期 / 版本 / 功能 / 输入 / 输出 / 时钟域 / 修改历史。
- 跨时钟域一律用 `async_fifo.v`，禁止用快时钟直接采样慢时钟。
- 端口命名采用 `clk_*`（时钟）、`rst_n`（低有效复位）、`*_valid`/`*_data`（握手）、`*_p*_n`（差分）。

## 当前进度（2026-08-31）

当前 **36 个 ModelSim testbench 全部 PASS**；P0-01~P0-07 均已实测 `[U]`，P0-08 `[C-sub]`，P0-09 完整媒体主链 `[C]`，P0 已冻结。完成状态按 `[U]/[C]/[S]/[B]/[L]` 口径记录：

| 子系统 | 状态 |
|---|---|
| top | `reset_gen` [U]；`system_top`/`hx4s20c_top`/`clk_gen` ❌ |
| storage | `sd_spi` / `sd_reader` / `fat32_scan` / `fat32_file_reader` / `bmp_parser` / `bmp_pixel_stream` / `vseq_reader` / `vseq_yuv_unpack` [U] |
| framebuf | `async_fifo`/`framebuffer_writer`/`frame_buffer_manager`/`line_buffer_pingpong`/`line_prefetcher` [U]；`sdram_arbiter` [U]；`sdram_adapter` [U] |
| display | 纯显示 RTL [U]；`hdmi_video_adapter` ❌；`tmds_encoder` [U] 仅 educational |
| audio | `tone_gen` / `audio_visual` [U]；`hdmi_audio_pack` [U] 仅 educational；`hdmi_audio_adapter` ❌ |
| interact | `key_filter` / `sw_filter` / `menu_fsm` / `seg_driver` / `dual_led` / `beep` 全部 [U] |
| app | `app_scenario` [U] |

> `fat32_file_reader` [U]：CASE0~CASE8 PASS（checks=18）；`bmp_pixel_stream` [U]：CASE0~CASE13 PASS（checks=13393）。
> P0-03/P0-04 [U] 文档见 `../docs/17~20`；P0-05/P0-06 [U] 文档见 `../docs/21~24`；P0-07 `[U]` / P0-08 `[C-sub]` 文档见 `../docs/27~30`；P0-09 `[C]` 与 P0 Freeze 见 `../docs/32~35`。
> 正式 SDRAM 使用 APUG011，正式 HDMI 使用 APUG092；vendor 目录只读，AI 只写 wrapper/adapter。
