# src — 设计代码（可综合 RTL）

模块按子系统分子目录。一个模块一个 `.v` 文件，文件名与模块名一致。

| 子目录 | 包含模块 |
|---|---|
| `top/` | `top.v`（顶层）、`clk_gen.v`、`reset_gen.v` |
| `storage/` | `sd_spi.v`、`sd_reader.v`、`fat32_scan.v`、`bmp_parser.v`、`vseq_reader.v`（视频帧序列） |
| `framebuf/` | `sdram_ctrl.v`、`frame_buffer.v`、`async_fifo.v` |
| `display/` | `vga_timing.v`、`image_enhance.v`、`image_scaler.v`、`transition.v`、`osd_overlay.v`、`tmds_encoder.v` |
| `audio/` | `hdmi_audio.v`、`tone_gen.v` |
| `interact/` | `key_filter.v`、`sw_filter.v`、`menu_fsm.v`、`seg_driver.v`、`dual_led.v`、`beep.v` |
| `app/` | `app_scenario.v`（信息发布终端业务） |

约束：
- 每个 `.v` 顶部写 IEEE 风格头注释：作者 / 日期 / 版本 / 功能 / 输入 / 输出 / 时钟域 / 修改历史。
- 跨时钟域一律用 `async_fifo.v`，禁止用快时钟直接采样慢时钟。
- 端口命名采用 `clk_*`（时钟）、`rst_n`（低有效复位）、`*_valid`/`*_data`（握手）、`*_p*_n`（差分）。

