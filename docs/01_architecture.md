# 01 · 系统架构（P0 → P4）

> 本文是当前唯一的架构权威。早期“模块 A：SD读取 / B：图像处理 / C：HDMI驱动”和“A/B/C 可做性分组”只作为历史记录，不再用于描述当前架构。

## 1. 架构原则

本项目是一个**无外部 CPU/MCU**的 FPGA 多媒体终端。架构按“可以被独立验收的工程阶段”划分，而不是按目录或人员划分：

| 阶段 | 架构职责 | 主要验收 |
|---|---|---|
| **P0 · Media Core** | 文件字节流 → BMP 像素 → 帧缓存写入/管理 → 抽象 SDRAM → 行预取 → 连续 RGB888 | `[C]`；已冻结 |
| **P1 · Vendor & Board Integration** | 用 APUG011/APUG092/PLL/官方约束把 P0 接入 EG4S20 真硬件 | `[S]` → `[B]`；下一阶段 |
| **P2 · Presentation** | HDMI 音频、OSD、亮度/对比度、转场、交互、音频可视化、应急叠加 | 子链 `[C]`，最终上板 `[B]` |
| **P3 · Short Video** | `.vseq` YUV444 短视频片段，帧序列读取、色彩转换、缩放、播放控制 | `[C]` → `[B]` |
| **P4 · Bonus / Stretch** | YUV420、省带宽读卡、SDIO、720p 等加分项 | 有余量再做；不阻塞基线 |

其中 **P0/P1 是系统地基**。P0/P1 未稳定前，不以新增展示特效替代底层闭环工作。

## 2. P0：已冻结的媒体基础链

P0 解决“媒体数据能否在不依赖厂商 IP 的情况下被正确组织成稳定显示像素流”。冻结主链为：

```text
fat32_file_reader
        ↓ file byte stream
bmp_parser / bmp_pixel_stream
        ↓ RGB888 + (x,y)
framebuffer_writer
        ↓ abstract write request
frame_buffer_manager ─── A/B ownership & frame-boundary swap
        ↓
   sdram_arbiter
        ↓
[ SDRAM backend boundary ]   ← P0 到此不关心厂商物理时序
        ↓
 line_prefetcher
        ↓ full-line fill
line_buffer_pingpong
        ↓
display-order RGB888, active line continuous
```

### 2.1 P0 固定契约

- **像素存储**：1 pixel = 1 个 32-bit word；RGB 为 `0x00RRGGBB`，后续 YUV444 保留 `0x00YYCbCr` 约定。
- **图片双缓冲**：Image A base=`0`，Image B base=`307200`，对应 640×480 每像素 1 word。
- **视频预留**：A/B/C 各 `76800` words（320×240）；规划总占用 `844800 / 2097152` words，不改变 P0 图片 A/B 契约。
- **无撕裂切换**：新帧只写 back buffer；writer 成功后仅在 display frame boundary 交换 front/back。
- **显示连续性**：`line_prefetcher` 提前读整行，`line_buffer_pingpong` 一边显示一边填下一行；active line 启动后不得出现 pixel-valid gap。
- **读写仲裁**：显示读取优先于后台写入；宁可新图加载变慢，也不能饿死显示。
- **BMP 基线**：24-bit、BI_RGB、bottom-up、4-byte row padding；支持非 54-byte pixel offset。
- **FAT32 基线**：512B sector、SDHC/SDXC、8.3 短名；`fat32_file_reader` 支持 fragmented FAT chain，以 `file_size` 为最终边界。

### 2.2 P0 已知边界

P0 `[C]` 并不等于“TF 卡到 HDMI 真板全通”。P0-09 从已知文件元数据/碎片 FAT 链驱动文件读取；`fat32_scan` 当前只扫描根目录第一 sector，真卡初始化、CMD58/CCS、完整目录遍历仍属于后续板级集成问题。

P0 也不模拟 APUG011 的全部 `busy/refresh/read-latency/4-word` 行为；这些差异必须由 P1 的 adapter/wrapper 吸收。

## 3. P1：把 P0 接到安路官方硬件路径

P1 不重写 P0，而是在冻结边界外增加 vendor adapter 和板级 top。

### 3.1 SDRAM 正式路径

```text
framebuffer_writer / line_prefetcher
              ↓
        sdram_arbiter
              ↓
        sdram_adapter          ← 我方写，吸收 vendor 时序差异
              ↓
 official APUG011 sdr_as_ram   ← vendor 源只读
              ↓
   EG_PHY_SDRAM_2M_32
              ↓
      EG4S20 internal SDRAM
```

APUG011 v1.2 application-side 已核对的关键语义为：21-bit word address、32-bit data、4-bit byte mask；读写互斥；操作前等待 `Sdr_init_done` 且避开 `Sdr_init_ref_vld/Sdr_busy`；读使能发出后约 **10 个 Sdr_clk** 由 `Sdr_rd_en` 标记有效返回；地址跳跃以 **4 words / 128 bit** 为粒度，每个新组从 `[1:0]==2'b00` 的地址开始。P1 的 adapter 必须保证 P0 看到的“accepted request → 有序且唯一 response”契约仍成立。

P1-01 当前实现采用保守、可证明的兼容映射（strict APUG011-like 链式 TB 已 `[C-sub]`）：每个 P0 单 word request 转成一个 4-word 对齐 micro-group。**写请求**仅目标 lane 使用 `App_wr_dm=4'b0000`，其余三个 lane 使用 `4'b1111` 完全屏蔽；**读请求**读完整组，但只把目标 lane 的 `Sdr_rd_en/Sdr_rd_dout` 返回 P0，同时整个 READ/IDLE 期间 `App_wr_dm` 必须保持 `4'b0000`。这是因为官方 reference `app_wrrd` 在读阶段保持 mask=0，且 SDRAM DQM 同样会屏蔽读数据输出。这样既不修改 P0 的任意 21-bit word 地址接口，也满足 APUG011 的 4-word 跳转规则。该策略后续可在 `[S]` 阶段依据实测时序/带宽决定是否增加连续 burst 优化，但优化不得改变 P0 外部契约。

`line_prefetcher.recovery_required` 的复位/flush 语义也必须在真实 memory provider 接入时明确：若失败事务已有 accepted outstanding read，不能让迟到 response 污染下一行。

### 3.2 HDMI 正式路径

正式比赛输出不再使用自研 `tmds_encoder` 作为主链：

```text
display-order RGB888
        ↓
hdmi_video_adapter
        ↓
official APUG092 HDMI1.4b Transmitter
        ↓ 4 × 10-bit TMDS words
hdmi_phy_wrapper (DEVICE="EG")
        ↓ EG_LOGIC_ODDR / official EG PHY pattern
        HDMI
```

`src/display/tmds_encoder.v` 仅保留为 `[U]` 教学/协议参考模块，不承担正式 HDMI protocol、Data Island、DDC/EDID 或物理串行化。

APUG092 的 active-line video interface 必须连续供数，因此 P0 的整行预取/乒乓 line buffer 是正式 HDMI 架构的一部分，而不是测试辅助结构。

### 3.3 音频正式路径

```text
tone_gen / later PCM source
        ↓ 48 kHz sample enable in pixel domain
hdmi_audio_adapter
        ↓ 24-bit L/R + valid
official APUG092 audio / ACR
        ↓
       HDMI
```

现有 `hdmi_audio_pack.v` 是 `[U]` 的 IEC60958 教学/参考 RTL，不进入正式 APUG092 主链。

### 3.4 顶层拆分

```text
system_top.v
  └─ 纯业务逻辑：storage / P0 media core / P2-P4 presentation

hx4s20c_top.v
  └─ 板级/vendor：PLL / APUG011 / APUG092 / PHY / board reset / physical IO
```

普通业务 RTL 不直接散落 `EG_*` primitive。vendor 源放在明确的 vendor 边界下，原则上只例化/包装，不重构官方源码。

## 4. 时钟与 CDC

当前显示基线：**640×480@60**。

- `clk_sys`：板载 50 MHz 系统控制基准。
- `clk_pix`：640×480 基线约 25.175 MHz。
- `clk_hdmi_ser`：正式 EG HDMI PHY 采用 **`clk_pix × 5` + DDR** 发送 10 bit/pixel；不是旧文档里的“10× fabric clock”。
- SDRAM 时钟：以 APUG011 官方示例/TD 实际配置为准，不在业务 RTL 中写死 vendor 时序。
- 跨时钟域的数据流必须使用明确 CDC（如 `async_fifo`）；慢速状态可按经过评审的同步方式处理，禁止快时钟直接采样异步事件。

720p60 接近本器件 True-LVDS/PHY 能力边界，只属于 P4 加分验证；**1080p 不纳入当前设计目标**。

## 5. P2/P3/P4 的接入位置

P2/P3/P4 不改变 P0 的存储/预取基本契约，而在稳定 RGB/YUV 像素流上扩展：

```text
P0/P3 media pixels
      ↓
scale / color-space / enhance / transition
      ↓
UI compositor (status / ticker / audio bar / emergency)
      ↓
hdmi_video_adapter → APUG092
```

UI 内部不再使用 `P0/P1/P2/P3` 作为图层名，避免与系统阶段冲突。统一称为：

```text
UI-L3 Emergency      最高优先级
UI-L2 Text/OSD
UI-L1 Audio visual
UI-L0 Base media     最低优先级
```

逐像素用覆盖标志 + 优先级 mux，不做窗口系统、复杂半透明、抗锯齿或完整 GPU 风格合成。

## 6. Vendor、约束与工程文件的红线

- APUG011/APUG092/PLL/IO 原语端口必须以安路官方文档和 HX4S20C 官方工程为准，禁止猜端口。
- 管脚、IOSTANDARD、时钟约束必须来自 **HX4S20C 官方约束/原理图**；不能为了“工程完整”绑定占位 pin。
- 当前 `constraints/eg4s20bg256_pins.cst` 与 `constraints/eg4s20bg256_timing.sdc` 是**历史占位模板，不是可上板约束**。
- 当前 `.al` 中 `ADC_FILE/SDC_FILE` 为空、TOP 为 `reset_gen`；因此当前工程没有资格标记 `[S]`。
- vendor 源文件为只读参考；AI/人工应通过 adapter/wrapper 对接，而不是直接重构官方 core。

## 7. 架构变更规则

P0 已进入维护模式。只有出现**官方文档、TD 综合/P&R、或真板证据**证明冻结契约无法实现时，才允许打开 P0：

1. 先在本文记录 Architecture Change Request：问题、证据、影响范围、替代方案；
2. 人工评审通过；
3. 再改 RTL/TB；
4. 重新跑受影响 `[U]` 与 P0 `[C]` 回归；
5. 更新 `03_plan_and_status.md` 的证据状态。

没有证据时，P1 的 vendor 差异优先由 adapter/wrapper 吸收。

### P1-02 APUG011 官方核验证边界

P1-01 已完成：`sdram_adapter [U]`，并通过 strict APUG011-like sub-chain `[C-sub]`。P1-02 不修改 P0/P1-01 契约，而是逐层替换 provider：

```text
Questa P1-02A:
sdram_arbiter / direct requester
  -> sdram_adapter
  -> apug011_core_wrapper
  -> official sdr_as_ram protected RTL
  -> official IS42s32200 behavioral SDRAM model

TD P1-02B synthesis harness path:
sdram_arbiter
  -> sdram_adapter
  -> official sdr_as_ram
  -> EG_PHY_SDRAM_2M_32
  -> EG4S20 internal 2M x 32 SDRAM
```

`apug011_core_wrapper` 只做 reset/port 薄封装，不重写厂商协议。P1-02A 以官方 IS42 外部模型验证 protected controller，已 **[C-sub] PASS(24)**；P1-02B 再连接 EG internal SDRAM primitive。

**P1-02A 已验证边界（2026-09-01）**：随包 `IS42s32200` 是 -7 timing model（`tCK=7ns`、`tRCD=21ns`），因此行为模型用 125 MHz/180° 做 model-safe 数据完整性验收；最终结果 tCK/tRCD/DQM 全部 0 violation，addr5/addr8 正确读回，official-core chain `[C-sub]`。该 125 MHz 只属于外部模型，不改变正式硬件目标。adapter 的正式契约维持：**READ/IDLE 的 App_wr_dm=0000；仅 ST_WRITE padding lane 使用 1111**。

**P1-02B TD6.2.1 集成边界**：主工程采用 TD 6.2.1 Engineer 168116 的原生 protected-source 组织。`global_def.v` 在 `.al` 中设置 `GlobalIncluded=true`；`sdr_as_ram.enc.v`、`sdr_init_ref.enc.v`、`sdr_wrrd.enc.v` 作为三个独立 Verilog source，禁止再通过项目自有 compile-unit `include` 聚合。TD-only `p1_apug011_td_top` 暂复用官方 25 MHz reference `clk_pll.v` 得到 150 MHz 0°/180°，并连接 `EG_PHY_SDRAM_2M_32`。该 harness 不绑定 HX4S20C pin；最终板卡仍需基于 50 MHz 板载时钟和官方 HX4S20C ADC/SDC 完成 P1-04。TD 6.2.1 时钟派生命令使用 `derive_clocks`，不再使用已 obsolete 的 `derive_pll_clocks`。
