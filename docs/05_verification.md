# 05 · 仿真与上板验证流程

## 1. 核心工作流（AI 写代码的闭环）

```
人类定接口契约(02_architecture)
  → Codex 按契约写 RTL + testbench
  → 人类用 ModelSim 仿真，看到波形/断言通过
  → 通不过 → 贴回 Codex 修改
  → 通过 → 集成到顶层 → 上板验证
```

> Architecture Freeze v1.0：主数据流、模块边界、vendor IP、SDRAM 像素格式和时钟架构已冻结；
> 如需变更，必须先更新架构文档并经人工审核，再修改 RTL。

## 2. 模块级仿真（每模块都要）
| 模块 | 激励 | 判据 |
|---|---|---|
| `sd_spi` | 模拟 SPI 时序 | 读扇区数据正确 |
| `fat32_scan` | 提供 FAT/目录结构 | 能定位目标 BMP/`.vseq` 文件索引 |
| `bmp_parser` | 提供 BMP 头部/像素 | 宽高/位深/像素偏移正确 |
| `vseq_reader` | 提供 `.vseq` 容器 | 宽/高/bpp/fps/帧数正确，每帧流式取数 |
| `color_space` | YCbCr 像素输入 | 输出 RGB 符合 BT.601 预期 |
| `image_scaler` | 任意分辨率像素 | 缩放后尺寸/内容正确 |
| `fat32_file_reader` | 碎片 FAT chain / file_size 边界 | 连续/碎片文件流正确，EOC 不作为唯一结束条件 |
| `bmp_pixel_stream` | bottom-up / padding / BGR | RGB/x/y/valid 正确 |
| `framebuffer_writer` | RGB pixel | 32bit word/地址/写请求正确 |
| `frame_buffer_manager` | frame swap | 禁止读写同一 buffer，swap 无撕裂 |
| `line_prefetcher` | SDRAM 读请求 | 行预取顺序正确 |
| `line_buffer_pingpong` | 随机 stall | 整行 valid 不中断 |
| `sdram_arbiter` | 多源读写 | read/write 互斥，随机仲裁正确 |
| `sdram_adapter` | APUG011 busy/latency | 非零读延迟、4-word 对齐、Sdr_init_done 时序正确 |
| `vga_timing` | 像素时钟 | 仅作为内部 timing/x-y scheduler |
| `hdmi_video_adapter` | APUG092 Video Interface | SOF/EOL、整行 valid 连续、外部 timing 与 Core 一致 |
| `hdmi_audio_adapter` | pixel domain 48k enable | 24bit L/R 与 APUG092 Audio Interface 正确 |
| `tmds_encoder` | educational/reference | unit test；不进入正式 HDMI 主链 |
| `image_enhance` | 像素 + 参数 | 亮度/对比度变化符合期望 |
| `osd_overlay` | 字库索引 + 坐标 | 叠加位置正确 |
| `key_filter` | 按键噪声 | 消抖输出边沿正确 |
| `menu_fsm` | 按键/拨码事件 | 状态跳转正确 |

### 2.1 P0-01 `fat32_file_reader` 回归记录（2026-08-31）

状态：**[U] UNIT PASS**。ModelSim 实际输出覆盖 CASE0~CASE8，最终：

```text
PASS: fat32_file_reader all adversarial cases passed (checks=18)
```

覆盖：zero-length、100B、512B、513B 跨 sector/cluster、fragmented `3→7→5` 且 `SPC=2`、premature EOC、free/invalid next cluster、FAT offset=508 边界、`sectors_per_cluster=0`。

该条记录本身只证明 `fat32_file_reader` 单元 `[U]`；完整链路已在 §2.5 的 P0-09 回归中取得 `[C]`。接口契约与测试向量分别见 `docs/13_fat32_file_reader_interface.md`、`docs/14_fat32_file_reader_test_vectors.md`。

### 2.2 P0-02 `bmp_pixel_stream` 回归记录（2026-08-31）

状态：**[U] UNIT PASS**。ModelSim 实际执行 CASE0~CASE13，最终：

```text
PASS: bmp_pixel_stream all adversarial cases passed (checks=13393)
```

覆盖：padding=0/1/2/3、width=1/2/3/4/17/640/641、`data_offset!=54` gap、bad magic、top-down/zero width 拒绝、premature `file_done`、上游 `file_ok=0`。

波形抽查 CASE0 首像素：`pixel_r=0x21`、`pixel_g=0x45`、`pixel_b=0x62`、`pixel_x=0`、`pixel_y=1`，与独立 pattern golden 一致，证明 BGR→RGB、bottom-up 映射及 `header_done` 与首 pixel B 同拍边界正确。

该条记录本身只证明 P0-02 单元 `[U]`；完整 BMP→framebuffer/media chain 已在 §2.5 取得 `[C]`。

### 2.3 P0-03/P0-04 framebuffer 回归记录（2026-08-31）

- `framebuffer_writer`：CASE0~CASE8 全部 PASS，`checks=1345`，状态 `[U]`。波形抽查首笔 accepted write：`addr=740`、`data=0x00112131`，对应 `(x=0,y=1), base=100, stride=640`。
- `frame_buffer_manager`：CASE0~CASE6 全部 PASS，`checks=166`，状态 `[U]`。首次 swap 后 `read_base=307200`、`write_base=0`、`read_frame_valid=1`、`read_width=640`。

两项仍只是 unit `[U]`，未证明 framebuffer/media chain `[C]`。

### 2.4 P0-05~P0-08 回归完成

P0-05/P0-06 已完成回归，命令保留如下：

```text
vsim -c -do ../sim_tb/framebuf/run_line_buffer_pingpong.do
vsim -c -do ../sim_tb/framebuf/run_line_prefetcher.do
```

实测结果：
- `line_buffer_pingpong`：CASE-GOLDEN+CASE0~CASE8 PASS（checks=2204），`0x0A40B2` RGB 全通道写入/读回一致，状态 `[U]`。
- `line_prefetcher`：CASE0~CASE13 PASS（checks=2713），状态 `[U]`。

P0-07/P0-08 冻结回归命令：

```powershell
vsim -c -do ../sim_tb/framebuf/run_sdram_arbiter.do
vsim -c -do ../sim_tb/framebuf/run_framebuffer_mock_chain.do
```

实测：
- `sdram_arbiter`：CASE0~CASE8 PASS（checks=39），状态 `[U]`。
- `framebuffer mock chain`：CASE-GOLDEN+CASE0~CASE3 PASS（checks=1495），状态 `[C-sub]`。


### 2.5 P0-09 完整媒体主链冻结回归（2026-08-31）

状态：**`[C] CHAIN PASS`**。ModelSim 实际执行 CASE-GOLDEN + CASE0~CASE3，最终：

```text
PASS: P0 media chain end-to-end all cases passed (checks=1698)
```

覆盖：
- CASE0：fragmented FAT `3→7`，17×12 24-bit BMP，文件 >512B，row padding=1；最终 17×12 display-order RGB 全量与独立 golden 一致。
- CASE1：640×2 baseline，8 个非连续 cluster，≥7 次 FAT traversal、≥8 个 data-cluster read；两条 640-pixel active line 无 `pixel_valid` 间隙。
- CASE2：无 reset 连续第三文件，`data_offset=70` + `0xEE` gap；A/B buffer 正常再次切换，gap 不被当像素。
- CASE3：终态 `arbiter protocol_error=0/outstanding=0`、mock pending/range/queue=0、linebuffer protocol/underflow=0、prefetch recovery=0，且读写命令均 >1400。

波形抽查 CASE0 首像素：`lb_pixel_data=0x125492`，等于独立 `expected_rgb(seed=0x12,x=0,y=0)`。

因此 P0 media chain 正式冻结为 `[C]`。该结论只覆盖纯 RTL + `mock_sdram`；**不等价于 APUG011/TD/板级 `[S]/[B]`**。

## 3. 上板验证清单
- [ ] 烧录成功，系统上电即进入轮播/片段播放。
- [ ] 每张图/每个片段显示正确（无翻转、无错位、无花屏）。
- [ ] 按键：播放/暂停/上下一张/片段切换均响应，无抖动误触发。
- [ ] 拨码：转场/亮度/对比度/算法切换有效且画面有体现。
- [ ] 音频：背景音/提示音经 HDMI 到音箱正常，且与画面同步。
- [ ] 视频：预载循环无卡顿；若流式，测实际帧率是否达标。
- [ ] 长稳：连续运行 ≥2h 无异常；反复快速切图/切片段 ≥100 次无花屏。
- [ ] 时钟域：无亚稳态导致的数据错乱（长时间观察）。

## 4. 量化指标（写进文档/演示）
- 输出分辨率/帧率：640×480@60（基线；720p 扩展记录实测）。
- 视频源规格：如 320×240 YUV420@30，实测播放帧率。
- 切图/切片段延迟：按键到画面变化时间（图像预载后 <100ms）。
- SD 实测吞吐：SPI / SDIO 各自 MB/s（决定视频档位）。
- 资源占用：LUT / DFF / ERAM / SDRAM / PLL 消耗。
- 稳定性：连续运行时长、反复切换次数无异常。
- 音画同步：音频与画面是否对齐。

