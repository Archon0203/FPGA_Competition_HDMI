> P0 Freeze Status (2026-08-31): P0-01~07 [U], P0-08 [C-sub], P0-09 [C]; P0 media chain 已冻结。P0-09 ModelSim: checks=1698 PASS。P0 [C] 仅代表纯 RTL + mock SDRAM 端到端通过，不代表 APUG011/APUG092、TD synthesis/P&R 或上板通过。权威冻结记录见 docs/35_P0_IMPLEMENTATION_FREEZE.md。

# 09 · 功能实现矩阵（做什么 + 用什么实现）

> 表格说明：`纯RTL`=可在 ModelSim 直接仿真、不用厂商 IP；`厂商IP/参考`=必须用 TD 里的官方 IP 或参考 lab_ex；`工具`=PC 端脚本。优先级：★★★ 必做 / ★★ 重点 / ★ 扩展。

| # | 功能 | 用什么实现 | 模块 | 依赖 | 优先级 | 状态(2026-08-28) |
|---|---|---|---|---|---|---|
| 1 | 时钟/复位 | PLL 生成像素/系统/SDRAM/SD/音频时钟 + 复位 | `clk_gen`/`reset_gen` | 厂商IP(PLL)+参考 | ★★★ | reset_gen ✅PASS; clk_gen ❌ 待人工PLL |
| 2 | SD/TF 读卡 | SPI 主机控制器（可扩展 SDIO） | `sd_spi`/`sd_reader` | 纯RTL+SD参考 | ★★★ | ✅PASS(字节SPI+命令FSM) |
| 3 | FAT32 文件系统 | 解析 MBR/FAT/目录，建文件索引 | `fat32_scan` | 纯RTL（可用 ROM 查表） | ★★★ | ✅PASS(根目录8.3,FAT32) |
| 4 | BMP 图片解析 | 解析 14B+40B 头，取宽高/位深/像素 | `bmp_parser` | 纯RTL | ★★★ | ✅PASS |
| 5 | 视频帧序列解析 | 解析自定义 `.vseq` 容器，并支持 YUV444 字节流解包 | `vseq_reader`/`vseq_yuv_unpack` | 纯RTL | ★★ | ✅PASS |
| 6 | 帧缓存(SDRAM) | SDRAM 控制器 + 双/三缓冲 + 异步 FIFO | `sdram_ctrl`/`frame_buffer`/`async_fifo` | 厂商IP/参考 | ★★★ | async_fifo ✅PASS; sdram_ctrl/frame_buffer ❌ 待人工IP |
| 7 | **行场时序** | 生成 HS/VS/DE + 像素坐标 | `vga_timing` | **纯RTL（本批已实现）** | ★★★ | ✅PASS |
| 8 | 色彩空间转换 | YCbCr→RGB（BT.601 定点矩阵，YUV420 先色度上采样） | `color_space`/`yuv420_upsample` | 纯RTL+DSP | ★★ | ✅PASS(color_space + yuv420_upsample) |
| 9 | 图像缩放 | 最近邻/双线性，任意分辨率→输出 | `image_scaler` | 纯RTL+行缓存 | ★★ | ✅PASS(最近邻坐标映射) |
| 10 | 图像增强 | 亮度/对比度/增益 | `image_enhance` | 纯RTL | ★★★ | ✅PASS |
| 11 | 转场特效 | 淡入淡出/滑动（双缓冲+alpha 混合） | `transition` | 纯RTL | ★ | ✅PASS(淡入/擦拭) |
| 12 | OSD 字幕 | 字符点阵 ROM + 行缓存 + 位置叠加 | `osd_overlay` | 纯RTL+字库ROM | ★★ | ✅PASS(8x16字模+位置叠加) |
| 13 | TMDS 编码 | TMDS 10bit 纯逻辑编码；串行化 + 差分输出另行人工 | `tmds_encoder`/官方 lab_ex | 纯RTL + 官方参考 | ★★★ | tmds_encoder ✅PASS(10bit 逻辑); 串行化/差分 ❌ 待官方参考 |
| 14 | HDMI 音频 | L-PCM/IEC60958 打包 + 注入 + 测试音/背景音 + 音频可视化 | `hdmi_audio_pack`/`tone_gen`/`audio_visual`/官方参考 | 官方参考+纯RTL | ★★★ | tone_gen ✅PASS; audio_visual ✅PASS(扩展⑤); hdmi_audio_pack ✅PASS(打包+偶校验); 注入 ❌ 待官方参考 |
| 15 | 按键/拨码消抖 | 防抖/边沿/长按 | `key_filter`/`sw_filter` | 纯RTL | ★★★ | ✅PASS |
| 16 | 交互状态机 | 播放/暂停/切图/调参/转场/应急 | `menu_fsm` | 纯RTL | ★★★ | ✅PASS |
| 17 | 状态显示 | 数码管/双色LED/蜂鸣 | `seg_driver`/`dual_led`/`beep` | 纯RTL | ★★ | ✅PASS |
| 18 | 应用场景 | 信息发布/应急广播业务 | `app_scenario` | 纯RTL(FMS) | ★★ | ✅PASS |
| 19 | 视频/图片转帧工具 | 转 `.vseq` + 做 SD 卡 | `tools/video_to_vseq.py`/`make_sd_card.py`/`gen_font.py` | PC 工具 | ★★ | video_to_vseq.py ✅(YUV420+回读校验); make_sd_card.py ✅(最小 FAT32 镜像); gen_font.py ✅(8x16 HEX) |
| 20 | 仿真验证 | ModelSim 建库、编译、跑 tb、看波形 | `sim_tb/tb_*.v` + `sim_work/` | ModelSim | ★★★ | 27 个 testbench 全部 ✅PASS |

## 实现顺序建议（与 docs/03 计划一致）
1. **地基（纯RTL）**：`vga_timing` → `async_fifo` → `sd_spi` → `key_filter` → `menu_fsm`（都能在 ModelSim 直接仿真）。
2. **数据通路（需官方参考）**：`sdram_ctrl`、`tmds_encoder`、`clk_gen(PLL)` —— 这 3 个需在 TD 里对照官方 lab_ex 例化 IP/原语，**人在 TD 做**。
3. **图像/视频处理（纯RTL）**：`color_space`、`image_scaler`、`image_enhance`、`transition`、`osd_overlay`。
4. **应用与工具**：`app_scenario`、`tools/*.py`。

> 第一批（本批）交付：`vga_timing`（RTL）+ `tb_vga_timing`（TB）+ `sim_work` 仿真工程。

