# 02 · 顶层架构设计

> 本文件是"顶层架构契约"。人类负责锁定本设计，Codex 按此逐模块实现。
> 端口、位宽、时钟域、存储划分以本文件为准；实现冲突时以本文件为准。

## 1. 功能抽象：三大模块

```
 A.SD读取 ──▶ B.视频/图像处理 ──▶ C.HDMI驱动 ──▶ 显示器
  (SPI读卡/文件系统/解帧)  (帧缓存+色彩空间+缩放+增强)  (行场时序+TMDS)
```

数据流：`SD卡 → FPGA缓存(SDRAM帧缓冲) → 图像处理(YCbCr→RGB+缩放+增强) → HDMI编码(TMDS) → 显示`

| 功能模块 | 职责 | RTL 子目录 |
|---|---|---|
| A. SD 读取 | SPI 读卡；FAT32 解析；BMP 解析；`.vseq` 视频帧序列解析 | `src/storage` |
| B. 视频/图像处理 | SDRAM 帧缓冲(双/三缓冲)；**YCbCr→RGB**；**图像缩放**；亮度/对比度增强；转场/OSD 叠加 | `src/framebuf` + `src/display` |
| C. HDMI 驱动 | 行场时序；**TMDS 编码**；串行化输出 | `src/display` |

> 三大模块是"功能抽象"，实现时再细分为子模块（见 `src/` 目录），内部用流水线并行。

## 2. 数据流（含视频）

```
                    ┌──────────────────────────── FPGA 内部（全部硬件，无 CPU）────────────────────────────┐
 SD/TF卡(BMP/.vseq) │  SPI读卡 → FAT32解析 → BMP解析/`.vseq`解帧 → 写FIFO → SDRAM帧缓存(图片双缓冲/视频三缓冲)│
  (SPI 或 SDIO)     │                                           │ 读FIFO                                    │
                    │  [加载/预载: 图片一次读入; 视频预载循环或流式]│                                           │
                    │                                           ▼                                           │
                    │                     显示处理流水线：YCbCr→RGB → 缩放 → 增强(亮度/对比度) → 转场 → OSD   │
                    │                        │                                                                │
                    │                        ▼                                                                │
                    │           行场时序 → 坐标 → TMDS编码 → 串行化 → HDMI输出                                │
                    │                                                                                        │
 按键/拨码 → 消抖 → 交互状态机 → 播放/暂停/切图/调参/转场/应急/字幕开关                                        │
 数码管/双色LED/蜂鸣 → 状态显示                                                                               │
 音频(测试音/背景音/PCM) → HDMI音频包(Data Island) → 音画同步                                                 │
                    └──────────────────────────────────────────────────────────────────────────────────────┘
```

## 3. 分层与模块划分

### L0 · 基础设施（`src/top`）
| 模块 | 职责 |
|---|---|
| `top` | 顶层例化、时钟/复位生成、IO 路由、引脚约束（引脚号见 `constraints/`） |
| `clk_gen` | 板载 50MHz + PLL 生成 `clk_pix`/`clk_tmds`/`clk_sdram`/`clk_sdo`/`clk_aud` 等 |
| `reset_gen` | 上电复位、各时钟域同步复位 |

### L1 · 存储与文件（`src/storage`）
| 模块 | 职责 |
|---|---|
| `sd_spi` | SD/TF 卡 SPI 模式控制器（块级读；若走流式可扩 SDIO 4-bit） |
| `sd_reader` | 高层次读卡状态机（CMD/ACMD 协商、读超时/重试） |
| `fat32_scan` | 分区表(MBR)/FAT/目录项解析，建立图片 + 视频文件索引 |
| `bmp_parser` | 解析 BMP（14B 文件头 + 40B 信息头），支持 24 位非压缩 |
| `vseq_reader` | 解析自定义 `.vseq` 容器（magic/宽/高/bpp/fps/帧数），流式取帧 |

### L2 · 帧缓存（`src/framebuf`）
| 模块 | 职责 |
|---|---|
| `sdram_ctrl` | SDRAM 控制器：命令/自动刷新/行预充电/读写仲裁；复用官方 IP/参考 |
| `frame_buffer` | 帧缓冲管理：图片**双缓冲**、视频**三缓冲**（ping-pong），地址映射 |
| `async_fifo` | 参数化跨时钟域异步 FIFO（SD→SDRAM、SDRAM→像素等） |

### L3 · 显示处理流水线（`src/display`）
| 模块 | 职责 |
|---|---|
| `vga_timing` | 生成 HSync/VSync/DE + 像素 X/Y 坐标（按输出分辨率参数化） |
| `color_space` | **YCbCr→RGB**（BT.601 定点矩阵）；YUV420 先色度上采样（最近邻/双线性） |
| `image_scaler` | 任意分辨率 → 输出分辨率（最近邻/双线性） |
| `image_enhance` | 亮度/对比度/增益调节 |
| `transition` | 淡入淡出/滑动转场（图片用；视频流不叠加转场） |
| `osd_overlay` | 字幕/时间戳叠加 + 字符点阵 ROM |
| `tmds_encoder` | TMDS 10bit 编码（数据/控制/同步）+ 串行化 + 差分输出；复用官方 HDMI 参考 |

### L4 · 音频（`src/audio`）
| 模块 | 职责 |
|---|---|
| `hdmi_audio` | HDMI 音频包（Data Island/L-PCM）生成与注入 |
| `tone_gen` | 测试音/背景音/提示音生成（查表或累加器） |

### L5 · 人机交互（`src/interact`）
| 模块 | 职责 |
|---|---|
| `key_filter` / `sw_filter` | 4 按键、4 拨码消抖 |
| `menu_fsm` | 主控状态机：播放/暂停/上下张/轮播/调参/切算法/应急/转场/字幕 |
| `seg_driver` | 8 位数码管扫描 + 译码 |
| `dual_led` / `beep` | 双色 LED 状态指示、蜂鸣器提示/应急 |

### L6 · 应用场景（`src/app`）
| 模块 | 职责 |
|---|---|
| `app_scenario` | "信息发布与应急广播终端"业务：图片轮播 + 短视频片段 + 时间戳 + 应急切换 + 音频联动 |

## 4. 关键接口契约（逻辑端口，物理引脚见官方约束）

### 4.1 `top`
```verilog
module top(
    input  wire       clk_50m,      // 板载 50MHz 有源时钟
    input  wire       rst_n,        // 复位(低有效)
    // SD/TF (SPI/SDIO)
    output wire       sd_cs_n, output wire sd_sclk,
    output wire       sd_mosi, input  wire sd_miso,
    // HDMI 输出 (R,G,B,Clk 差分；引脚取自官方约束)
    output wire [3:0] hdmi_tmds_p, output wire [3:0] hdmi_tmds_n,
    // 人机交互
    input  wire [3:0] key, input  wire [3:0] sw,
    output wire [3:0] led, output wire [7:0] seg_sel, output wire [7:0] seg_data,
    output wire buzzer,
    output wire uart_txd, input wire uart_rxd
);
```

### 4.2 关键数据接口（供 Codex/testbench 对齐）
| 通道 | 源 → 目的 | 位宽 | 时钟域 |
|---|---|---|---|
| `sd_data` | sd_reader → async_fifo | 16 | `clk_sdo` |
| `fb_wr` | frame_buffer 写总线 | 32 | `clk_sdram` |
| `px_valid/px_data` | frame_buffer → 显示流水线 | 24 (RGB888) | `clk_pix` |
| `yuv_valid/yuv_data` | vseq_reader → color_space | 24 (YUV444) | `clk_pix` |
| `para_val` | menu_fsm → image_enhance | 8 | `clk_pix` |
| `osd_char` | osd_overlay ← 字库 ROM | 8 | `clk_pix` |
| `key_event` | key_filter → menu_fsm | 4 | `clk_sys` |

> 所有跨时钟域数据必须经 `async_fifo`，禁止用快时钟直接采样慢时钟信号。

## 5. 时钟域与 CDC

| 时钟 | 频率(建议) | 用途 |
|---|---|---|
| `clk_sys` | 50MHz | 系统控制/交互状态机 |
| `clk_pix` | 25.175MHz | 640×480@60 像素时钟（720p 时为 74.25MHz） |
| `clk_tmds` | ×10 像素时钟 | TMDS 串行化位时钟（~252/742MHz） |
| `clk_sdo` | 12.5/25MHz | SD 读卡 |
| `clk_sdram` | ~100MHz | SDRAM 主时钟 |
| `clk_aud` | 12.288MHz | HDMI 音频包 |

CDC 点：SD→SDRAM（写）、SDRAM→像素（读）、菜单(50M)→像素、音频(12.288M)→TMDS，均以异步 FIFO 桥接。

## 6. 存储映射

### SDRAM（2M×32bit ≈ 8MB）
| 区域 | 大小 | 用途 |
|---|---|---|
| 图片帧缓冲 A | 640×480×3 ≈ 230,400 word | 当前图片 |
| 图片帧缓冲 B | 640×480×3 ≈ 230,400 word | 下一张/转场暂存（双缓冲） |
| 视频三帧缓冲 | 320×240×2 × 3 ≈ 115,200 word | 视频帧源（三缓冲） |
| 加载暂存区 / 文件索引 | 若干 word | SD 预载/索引缓存 |

> 640×480×3 = 921,600B = 230,400 word；双缓冲 460,800 + 视频 115,200 ≈ 576,000 word << 2,097,152 word，余量充足。
> 视频帧以 320×240 YUV/YCbCr 存，显示时经缩放放大到输出分辨率（省带宽与存储）。

### ERAM（64×9Kb + 16×32Kb ≈ 136KB）
| 用途 | 大小 |
|---|---|
| 行缓存（缩放/色彩空间/增强） | 640×3×2~3 行 ≈ 6KB |
| 异步 FIFO | 若干 × 512~2048 word |
| OSD 字符点阵 ROM | 8×16 × ≤256 字 ≈ 32KB |
| 音频/像素 FIFO | 若干 KB |

## 7. 分辨率与带宽预算

### 7.1 输出分辨率（显示端）
- **基线 640×480@60**（像素时钟 25.175MHz，TMDS 位时钟 ~252MHz）：与官方 `lab_ex_5` 一致，资源与时序已验证可行。
- **720p 扩展**（1280×720@60，像素 74.25MHz，TMDS ~742MHz）：**需实测** FPGA 逻辑串行化极限，作为加分探索；**1080p 不作为承诺指标**。

### 7.2 视频源读取带宽（成不成立的关键）
| 视频源 | 每帧 | @30fps 需带宽 | 可行读取方式 |
|---|---|---|---|
| 640×480 YUV420 | 460,800B | 13.8 MB/s | SDIO 4-bit@25MHz(12.5)压线 |
| 320×240 YUV420 | 115,200B | 3.46 MB/s | SPI@25MHz(3.1)压线 / SDIO 宽松 |
| 320×240 YUV444 | 230,400B | 6.91 MB/s | SDIO 4-bit 宽松 |

**结论**：视频主档取 **320×240 YUV420 @ 25–30fps**（配 SDIO 或预载循环）；若走预载循环则可在 SDRAM 内无缝回转，**不依赖实时 SD 读速**。显示时放大到 640×480。

## 8. 关键技术选型与复用点

1. **HDMI TMDS**：EG4S20 无专用 HDMI 硬核，用输出串行化(OSERDES/移位)+差分 IO 输出（3 数据通道+1 时钟通道）；**务必以官方 lab_ex 参考为准**，Codex 只改应用逻辑、不改参考接口。
2. **SDRAM 控制器**：复用官方 IP/参考，关注自动刷新、双端口仲裁、读写带宽。
3. **SD 卡**：图片/预载用 SPI；实时流式可扩 SDIO 4-bit（复杂度高，两周内调不通则退回 SPI+预载循环）。
4. **色彩空间**：视频帧存 YCbCr（YUV），按 BT.601 定点矩阵转 RGB；YUV420 先色度上采样。
5. **音频**：HDMI 音频包经 Data Island 注入；测试音/背景音用查表/累加器，或播放预采样 PCM。

## 9. 交互设定（示例）
| 输入 | 功能 |
|---|---|
| KEY0 | 播放/暂停 |
| KEY1 | 下一张/下一片段 |
| KEY2 | 上一张/上一片段 |
| KEY3 | 进入/切换"应急信息页" 或 长按切换轮播 |
| SW0–1 | 转场模式（无/淡入淡出/滑动） |
| SW2–3 | 亮度/对比度档位（或 增强/算法档位切换） |

数码管显示图号+播放状态/参数档位；双色 LED：播放(绿)/暂停(红)/告警(闪烁)。
