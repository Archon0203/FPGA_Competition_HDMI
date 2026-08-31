# 02 · 顶层架构设计（2026-08-31，基于官方开发板资料修订）

> 本文是顶层架构契约。端口、位宽、时钟域、存储划分和 vendor IP 使用以本文件为准。
> 普通 `src/` 模块只做可综合业务逻辑；厂商原语、PHY、PLL、板级 IO 全部收敛到 `hx4s20c_top.v`。

## 0. Architecture Freeze v1.0 — 2026-08-31

自本版本起，AI Agent 不得因实现方便、局部优化或新的个人建议自行改变主数据流、模块边界、vendor IP 选择、SDRAM 像素格式及时钟架构。

仅当以下证据证明当前契约存在冲突时，才能提出 Architecture Change Request：

- 安路官方资料；
- TD 综合/P&R/时序结果；
- 真实开发板测试结果。

变更流程：

1. 先修改架构文档；
2. 经人工审核通过；
3. 再修改 RTL。

## 1. 正式硬件链路

### 1.1 HDMI 主链：使用官方 APUG092

```text
RGB888 pixel stream
  -> hdmi_video_adapter
  -> hdmi_1_4b_transmitter_core_wrapper
  -> hdmi_phy_wrapper(DEVICE="EG")
  -> EG_LOGIC_ODDR
  -> HX4S20C HDMI 物理输出
```

官方 APUG092 Core 负责：

- HDMI protocol
- TMDS encoding
- Video timing mapping
- Data Island
- HDMI Audio
- ACR
- DDC/EDID

现有 `tmds_encoder.v`、`hdmi_audio_pack.v` 保留为 educational/reference RTL 和 unit test，**不得删除**，但不得作为正式 HDMI 主链。

禁止从零重新实现 HDMI Data Island。

### 1.2 HDMI 时钟定义

删除旧的 `clk_tmds = pixel_clock × 10`。

新定义：

```text
clk_pix        : 像素时钟，640x480 基线
clk_hdmi_ser   : clk_pix × 5
```

10bit TMDS 采用 5x clock + ODDR 双边沿串行化。

分辨率目标：

- 640x480：正式基线。
- 720p：仅作为最终加分项。
- 1080p60：从项目目标删除。

APUG092 自带工程是 PH1A/AP106 示例，其 PLL、pin.adc、板级 top 不能直接复制到 HX4S20C。

## 2. SDRAM 正式后端：使用官方 APUG011

```text
frame_buffer_manager  (控制/地址分配)
  ├─ framebuffer_writer   (写请求源)
  └─ line_prefetcher      (读请求源)
          └─ line_buffer_pingpong
  └─────────────┐
                v
          sdram_arbiter
                v
          sdram_adapter
                v
  official APUG011 sdr_as_ram
                v
      EG_PHY_SDRAM_2M_32
```

`frame_buffer_manager` 只负责控制、地址分配和读写保护；
`framebuffer_writer` 和 `line_prefetcher` 才是 SDRAM request source，
统一经 `sdram_arbiter` 访问 `sdram_adapter`。

禁止自行重新实现完整 SDRAM controller。

`sdram_adapter` 必须正确处理：

- `Sdr_init_done`
- `Sdr_init_ref_vld` / `Sdr_busy`
- `App_wr_en` / `addr` / `data` / `dm`
- `App_rd_en` / `addr`
- `Sdr_rd_en` / `Sdr_rd_dout`
- read/write 互斥
- 非零读延迟
- 4-word 对齐/连续访问规则
SDRAM read response 必须经 sdram_adapter → sdram_arbiter 返回给发起请求的 line_prefetcher；只有 line_prefetcher 写 line_buffer_pingpong，arbiter/adapter 不直接写 line buffer。
### 2.1 SDRAM 像素格式

统一一个像素一个 32bit word：

```text
RGB:    0x00RRGGBB
YUV444: 0x00YYCbCr
```

禁止做 24bit 紧凑跨 word packing。

### 2.2 SDRAM 映射

所有 frame base address 保证 4-word 对齐。

| 区域 | 大小 | 用途 |
|---|---:|---|
| Image A | 307200 words | 640×480 RGB 当前帧 |
| Image B | 307200 words | 640×480 RGB 下一帧/转场 |
| Video A | 76800 words | 320×240 YUV444 三缓冲 A |
| Video B | 76800 words | 320×240 YUV444 三缓冲 B |
| Video C | 76800 words | 320×240 YUV444 三缓冲 C |
| 加载暂存/索引 | 若干 word | FAT32 索引与预载 |

总占用约：

```text
307200 × 2 + 76800 × 3 = 844800 words
```

远小于 2M×32bit SDRAM。

## 3. 存储与文件输入

```text
SD/TF
  -> sd_spi / sd_reader
  -> fat32_scan
  -> fat32_file_reader
  -> bmp_parser / bmp_pixel_stream
  -> framebuffer_writer
  -> SDRAM frame buffer
```

当前 SD 约束：

- 只支持 SDHC/SDXC block addressing。
- `sd_reader` 上电通过 `sd_spi` 发送 10 个 `0xFF` 产生 80 SCLK。
- 初始化成功后后续 block 直接 CMD17，不重复初始化。
- 响应/token 前 `0xFF` 有总等待上限。

FAT32 baseline：

- 512-byte sector。
- SDHC/SDXC。
- 8.3 short filename。
- 不依赖 LFN。
- `fat32_scan` 当前只索引根目录第一 sector。
- `fat32_file_reader` 必须支持 fragmented FAT chain。
- 文件读出以 `file_size` 为最终边界，不能仅靠 EOC 结束。

BMP baseline：

- 24-bit。
- BI_RGB / uncompressed。
- baseline 支持 bottom-up。
- 必须处理 4-byte row padding。

## 4. 显示流水线与行缓冲

APUG092 Video Interface 要求一行有效像素不能断流。

正式路径：

```text
SDRAM
  -> line_prefetcher
  -> line_buffer_pingpong / pixel FIFO
  -> continuous active line
  -> hdmi_video_adapter
  -> APUG092
```

禁止 SDRAM 逐像素直接驱动 HDMI。

`vga_timing` 在 APUG092 架构下不再直接产生 HDMI 同步信号；
它只作为内部 timing/x-y scheduler，生成 DE、x、y，用于文件流/OSD/line prefetch 调度。
最终由 `hdmi_video_adapter` 把这些内部时序转换成 APUG092 的 Video Interface。

## 5. 模块职责

### 5.1 新增正式模块

| 模块 | 路径 | 职责 |
|---|---|---|
| `fat32_file_reader` | `src/storage/` | FAT chain、cluster→LBA、连续文件字节流、file_size 终止 |
| `bmp_pixel_stream` | `src/storage/` | BGR→RGB、bottom-up、padding、x/y、pixel_valid |
| `framebuffer_writer` | `src/framebuf/` | RGB pixel → 32bit word/address/write request |
| `frame_buffer_manager` | `src/framebuf/` | 多 buffer 管理、frame swap、读写保护 |
| `line_prefetcher` | `src/framebuf/` | SDRAM 行预取，产生读请求并填入 `line_buffer_pingpong` |
| `sdram_arbiter` | `src/framebuf/` | 多请求源仲裁、read/write 互斥 |
| `sdram_adapter` | `src/framebuf/` | 适配 APUG011 接口与读写时序 |
| `line_buffer_pingpong` | `src/framebuf/` | 连续 active line 缓冲，消除 SDRAM latency/refresh stall |
| `hdmi_video_adapter` | `src/display/` | 项目像素流 → APUG092 Video Interface |
| `hdmi_audio_adapter` | `src/audio/` | pixel domain 下 24bit L/R → APUG092 Audio Interface |

职责分离要求：

- `bmp_pixel_stream` 只产生像素流，不感知 SDRAM 接口。
- `framebuffer_writer` 只负责像素 → SDRAM word/地址/写请求。
- `frame_buffer_manager` 只管理 buffer 选择与边界。
- `line_prefetcher` 只负责把显示行预取到 `line_buffer_pingpong`。
- `sdram_adapter` 只做 APUG011 接口适配，不重写 controller。

## 6. 音频基础版

基础版本取消独立 `clk_aud` 域。

官方 HDMI Audio Interface 工作在 `I_pixel_clk` 域。

```text
pixel clock
  -> 48k sample enable(相位累加器/Bresenham 分数分频，平均 48kHz clock-enable)
  -> tone_gen
  -> 24bit left/right
  -> official HDMI Core
```

复用官方 `audio_arc_calculate` 产生 ACR。

约束：

- 48k sample enable 必须用相位累加器/Bresenham 型分数分频产生平均 48kHz clock-enable。
- 禁止创建新的 fabric audio clock。
- 禁止简单整数除法假装精确 48kHz。

只有未来加入异步 PCM/I2S 源时才增加 audio CDC。

## 7. 顶层拆分与 vendor 隔离

| 文件 | 职责 |
|---|---|
| `system_top.v` | 纯业务逻辑：文件流、framebuffer、显示/音频 adapter、交互状态机 |
| `hx4s20c_top.v` | PLL、官方 SDRAM、官方 HDMI PHY、SD/HDMI physical IO、board reset、vendor primitive、constraints |

约束：

- 普通 `src/` 模块不得出现 `EG_PHY_*`、`EG_LOGIC_*`。
- vendor 代码只允许在 `hx4s20c_top.v` 或 vendor wrapper 中出现。

### 7.1 vendor 目录

```text
src/vendor/anlogic/hdmi_apug092/
src/vendor/anlogic/sdram_apug011/
```

vendor 目录官方代码禁止修改。

AI 只能：

- 读取
- 解释
- 例化
- 写 wrapper/adapter

不得重构 vendor 文件。

## 8. 模块完成状态

状态从单个 ✅ 改为：

```text
[U] UNIT PASS
[C] CHAIN PASS
[S] TD SYNTH/P&R PASS，且 timing/resource/RAM inference/clock constraints 检查通过
[B] BOARD PASS
[L] LONG-RUN PASS
```

任何模块只通过 unit test，不得写“系统功能已完成”。

## 9. 实现优先级

```text
P0:
  fat32_file_reader
  bmp_pixel_stream
  framebuffer_writer
  frame_buffer_manager
  line_prefetcher
  line_buffer_pingpong
  sdram_arbiter

  FAT32 image
    -> ...
    -> framebuffer_writer ─┐
                          ├→ sdram_arbiter → mock SDRAM
       line_prefetcher ───┘
                          ↓
                 line_buffer_pingpong
                          ↓
             display-order RGB stream
                          ↓
               Python golden compare

  CHAIN PASS

P1:
  sdram_adapter 对接 APUG011
  官方 APUG011 simulation/synthesis
  hdmi_video_adapter + APUG092 EG wrapper
  hx4s20c board_top + ADC/SDC
  完整 TD synthesis/P&R/timing

P2:
  基础 HDMI audio
  OSD / transition / brightness / audio visual

P3:
  YUV444 短视频

P4:
  YUV420 / SDIO / 720p
```

在 P0/P1 完成以前，禁止新增其他展示特效。

## 10. Testbench 原则

协议 TB 必须包含 adversarial tests。

SD：

- random response delay
- token delay
- timeout
- error token
- 连续多 block
- 含 0xFF 的 command argument

FAT32：

- 连续 cluster
- 碎片 cluster chain
- 跨 sector
- 文件大小不是 sector 整数倍
- EOC

BMP：

- width 640 / 641 / 17
- padding
- bottom-up
- 多文件连续解析

SDRAM：

- random busy
- refresh stall
- read latency
- read/write arbitration
- 禁止同时 read/write

Frame buffer：

- frame boundary swap
- 禁止读写同一 buffer
- underflow/overflow
- random memory stall

HDMI：

- 整行 valid 连续
- SOF/EOL 正确
- 外部 timing 与 Core 参数一致


## 11. P0 Implementation Freeze v1.0 — 2026-08-31

P0 已完成最终端到端 ModelSim 回归并冻结。冻结证据：

```text
P0-01~P0-07  [U]
P0-08         [C-sub]
P0-09         [C]

PASS: P0 media chain end-to-end all cases passed (checks=1698)
```

冻结主链：

```text
fat32_file_reader
 -> bmp_parser / bmp_pixel_stream
 -> frame_buffer_manager / framebuffer_writer
 -> sdram_arbiter
 -> SDRAM backend boundary
 -> line_prefetcher
 -> line_buffer_pingpong
 -> display-order RGB888
```

冻结规则：

1. P1 不得因 APUG011/APUG092 接入方便而重构上述 P0 模块职责、像素格式、地址语义或 A/B buffer ownership。
2. APUG011 的 `busy/init/read latency/4-word` 差异由 `sdram_adapter`/wrapper 优先吸收。
3. APUG092 的 Video/Audio Interface 差异由 `hdmi_video_adapter`/`hdmi_audio_adapter` 优先吸收。
4. 若 TD synthesis/P&R、官方文档或真板证明冻结契约不可实现，必须走 Architecture Change Request：先改文档并人工审核，再改 RTL。
5. `[C]` 只代表纯 RTL + mock SDRAM 的逻辑链闭环；不等于 `[S]`、`[B]` 或 `[L]`。
