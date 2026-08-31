# 09 · 功能实现矩阵（做什么 + 用什么实现）

> 表格说明：`纯RTL`=可在 ModelSim 直接仿真、不用厂商 IP；`厂商IP/参考`=必须用 TD 里的官方 IP 或参考 lab_ex；`工具`=PC 端脚本。优先级：★★★ 必做 / ★★ 重点 / ★ 扩展。

| # | 功能 | 用什么实现 | 模块 | 依赖 | 优先级 | 状态(2026-08-31) |
|---|---|---|---|---|---|---|
| 1 | 时钟/复位 | PLL 生成 clk_pix、clk_hdmi_ser=clk_pix×5、clk_sdram、clk_sdo + 复位 | `clk_gen`/`reset_gen` | 厂商IP(PLL)+参考 | ★★★ | reset_gen [U]; clk_gen ❌ 待人工 PLL |
| 2 | SD/TF 读卡 | SPI 主机控制器（可扩展 SDIO） | `sd_spi`/`sd_reader` | 纯RTL+SD参考 | ★★★ | ✅PASS(字节SPI+命令FSM) |
| 3 | FAT32 文件系统 | 根目录索引 + FAT chain 文件流 | `fat32_scan`/`fat32_file_reader` | 纯RTL | ★★★ | `fat32_scan` [U]；`fat32_file_reader` [U]；P0 完整媒体链 `[C]` |
| 4 | BMP 图片解析/像素流 | header + BGR/padding/bottom-up 解包 | `bmp_parser`/`bmp_pixel_stream` | 纯RTL | ★★★ | 两模块均 [U]；`bmp_pixel_stream` CASE0~CASE13 PASS（checks=13393） |
| 5 | 视频帧序列解析 | 解析自定义 `.vseq` 容器，并支持 YUV444 字节流解包 | `vseq_reader`/`vseq_yuv_unpack` | 纯RTL | ★★ | ✅PASS |
| 6 | 帧缓存(SDRAM) | writer/manager + arbiter/adapter/line buffer + APUG011 | `framebuffer_writer`/`frame_buffer_manager`/`sdram_arbiter`/`sdram_adapter`/`line_buffer_pingpong`/APUG011 | 纯RTL+厂商IP/参考 | ★★★ | P0-03 writer [U]（1345）、P0-04 manager [U]（166）、P0-05 line buffer [U]（2204）、P0-06 prefetcher [U]（2713）；P0-07 arbiter [U]；P0-08 framebuffer/mock `[C-sub]`；P0-09 media chain `[C]`；adapter [U] |
| 7 | **内部 timing/x-y scheduler** | APUG092 架构下只调度 DE/x/y，不直接产生 HDMI 同步 | `vga_timing` | **纯RTL（已实现）** | ★★★ | [U] |
| 8 | 色彩空间转换 | YCbCr→RGB（BT.601 定点矩阵，YUV420 先色度上采样） | `color_space`/`yuv420_upsample` | 纯RTL+DSP | ★★ | ✅PASS(color_space + yuv420_upsample) |
| 9 | 图像缩放 | 最近邻/双线性，任意分辨率→输出 | `image_scaler` | 纯RTL+行缓存 | ★★ | ✅PASS(最近邻坐标映射) |
| 10 | 图像增强 | 亮度/对比度/增益 | `image_enhance` | 纯RTL | ★★★ | ✅PASS |
| 11 | 转场特效 | 淡入淡出/滑动（双缓冲+alpha 混合） | `transition` | 纯RTL | ★ | ✅PASS(淡入/擦拭) |
| 12 | OSD 字幕 | 字符点阵 ROM + 行缓存 + 位置叠加 | `osd_overlay` | 纯RTL+字库ROM | ★★ | ✅PASS(8x16字模+位置叠加) |
| 13 | 正式 HDMI 输出 | 使用官方 APUG092；adapter 转 Video Interface | `hdmi_video_adapter`/APUG092 | 官方 vendor IP | ★★★ | `tmds_encoder` [U] 仅 educational；正式主链 ❌ 待 APUG092 集成 |
| 14 | 正式 HDMI 音频 | 使用官方 APUG092；pixel domain 48k sample enable + 24bit L/R | `hdmi_audio_adapter`/APUG092 | 官方 vendor IP | ★★★ | `hdmi_audio_pack` [U] 仅 educational；正式主链 ❌ 待 APUG092 集成 |
| 15 | 按键/拨码消抖 | 防抖/边沿/长按 | `key_filter`/`sw_filter` | 纯RTL | ★★★ | ✅PASS |
| 16 | 交互状态机 | 播放/暂停/切图/调参/转场/应急 | `menu_fsm` | 纯RTL | ★★★ | ✅PASS |
| 17 | 状态显示 | 数码管/双色LED/蜂鸣 | `seg_driver`/`dual_led`/`beep` | 纯RTL | ★★ | ✅PASS |
| 18 | 应用场景 | 信息发布/应急广播业务 | `app_scenario` | 纯RTL(FMS) | ★★ | ✅PASS |
| 19 | 视频/图片转帧工具 | 转 `.vseq` + 做 SD 卡 | `tools/video_to_vseq.py`/`make_sd_card.py`/`gen_font.py` | PC 工具 | ★★ | video_to_vseq.py [U](YUV444 默认+回读校验); make_sd_card.py [U](最小 FAT32 镜像); gen_font.py [U](8x16 HEX) |
| 20 | 仿真验证 | ModelSim 建库、编译、跑 tb、看波形 | `sim_tb/tb_*.v` + `sim_work/` | ModelSim | ★★★ | **36 个 testbench PASS / 36 个 TB**；P0-07 `[U]`（39）、P0-08 `[C-sub]`（1495）、P0-09 `[C]`（1698） |

## 实现顺序建议（与 docs/03 计划一致）
1. **地基（纯RTL）**：`vga_timing` → `async_fifo` → `sd_spi` → `key_filter` → `menu_fsm`（都能在 ModelSim 直接仿真）。
2. **P0 媒体输入链**：`fat32_file_reader`、`bmp_pixel_stream` **[U]**；`framebuffer_writer`/`frame_buffer_manager` **[U]**；`line_prefetcher`/`line_buffer_pingpong`/`sdram_arbiter` 已 [U]；framebuffer/mock `[C-sub]`；FAT32/BMP→display-order RGB 端到端 `[C]`，P0 已冻结。
3. **P1 官方 vendor/TD**：`sdram_adapter`(APUG011)、`hdmi_video_adapter`/`hdmi_audio_adapter`(APUG092)、`hx4s20c_top`、constraints、TD synthesis/P&R。
3. **图像/视频处理（纯RTL）**：`color_space`、`image_scaler`、`image_enhance`、`transition`、`osd_overlay`。
4. **应用与工具**：`app_scenario`、`tools/*.py`。

> 第一批（本批）交付：`vga_timing`（RTL）+ `tb_vga_timing`（TB）+ `sim_work` 仿真工程。

