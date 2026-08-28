# src — 设计代码（可综合 RTL）

模块按子系统分子目录。一个模块一个 `.v` 文件，文件名与模块名一致。

| 子目录 | 包含模块 |
|---|---|
| `top/` | `top.v`（顶层）、`clk_gen.v`、`reset_gen.v` |
| `storage/` | `sd_spi.v`、`sd_reader.v`、`fat32_scan.v`、`bmp_parser.v`、`vseq_reader.v`、`vseq_yuv_unpack.v`（YUV444 解包） |
| `framebuf/` | `sdram_ctrl.v`、`frame_buffer.v`、`async_fifo.v` |
| `display/` | `vga_timing.v`、`color_space.v`、`yuv420_upsample.v`、`image_enhance.v`、`image_scaler.v`、`transition.v`、`osd_overlay.v`、`tmds_encoder.v` |
| `audio/` | `tone_gen.v`、`audio_visual.v`、`hdmi_audio_pack.v`、`hdmi_audio.v` |
| `interact/` | `key_filter.v`、`sw_filter.v`、`menu_fsm.v`、`seg_driver.v`、`dual_led.v`、`beep.v` |
| `app/` | `app_scenario.v`（信息发布终端业务） |

约束：
- 每个 `.v` 顶部写 IEEE 风格头注释：作者 / 日期 / 版本 / 功能 / 输入 / 输出 / 时钟域 / 修改历史。
- 跨时钟域一律用 `async_fifo.v`，禁止用快时钟直接采样慢时钟。
- 端口命名采用 `clk_*`（时钟）、`rst_n`（低有效复位）、`*_valid`/`*_data`（握手）、`*_p*_n`（差分）。

## 当前进度（2026-08-28）

纯 RTL 模块已全部实现并通过 ModelSim 仿真（27 个 testbench PASS）：

| 子系统 | 状态 |
|---|---|
| top | `reset_gen` ✅；mini-top 显示链集成 ✅(`tb_mini_top`)；`top`/`clk_gen` ❌ 待人工 PLL 与集成 |
| storage | `sd_spi` / `sd_reader` / `fat32_scan` / `bmp_parser` / `vseq_reader` / `vseq_yuv_unpack` 全部 ✅ |
| framebuf | `async_fifo` ✅；`sdram_ctrl`/`frame_buffer` ❌ 待厂商 IP |
| display | `vga_timing` / `image_enhance` / `color_space` / `yuv420_upsample` / `image_scaler` / `transition` / `osd_overlay` / `tmds_encoder`(10bit 逻辑) ✅；TMDS 串行化/差分 ❌ 待官方参考 |
| audio | `tone_gen` ✅ / `audio_visual` ✅ / `hdmi_audio_pack` ✅；`hdmi_audio` 注入 ❌ 待官方参考 |
| interact | `key_filter` / `sw_filter` / `menu_fsm` / `seg_driver` / `dual_led` / `beep` 全部 ✅ |
| app | `app_scenario` ✅ |

> 厂商 IP / 官方参考模块（PLL、SDRAM、TMDS、HDMI 音频）不编端口，由人工在 TD GUI 例化核对后再集成。
