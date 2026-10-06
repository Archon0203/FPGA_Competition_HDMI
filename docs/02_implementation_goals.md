# 02 · 实现目标与验收边界

> 本文定义目标和证据门槛，不作为当前进度日志。当前 PASS/未通过/待验证状态只以 `docs/03_plan_and_status.md` 为准。

## 1. 最终作品目标

在两块 HX4S20C / EG4S20BG256 上实现无外部 CPU/MCU 的双板 HDMI 图片信息发布终端：

```text
TF/FAT32
  ↓
BMP 图片
  ↓
internal SDRAM framebuffer
  ↓
real-time display pipeline
  ↓
APUG092 HDMI video/audio
  ↓
HDMI display
```

## 2. 稳定基线证据（非当前状态权威）

- P0 media core：`[C] PASS(1698)`；
- P1-02B APUG011 internal SDRAM backend：150 MHz `[S]`；
- P1-04C HDMI_B：`[B] PASS`；
- **P1-05A internal SDRAM framebuffer → HDMI_B：TD6.2.1 routed `[S] PASS`；TD6.2.1 真板 `[B] PASS`。**
- **M1ABC 双板可视化控制闭环：115200 framed UART 与 deterministic 页面真板门禁已通过；其用途是控制面基线，不代表真实媒体切换。**
- **M2 已取得 TF/FAT32/BMP → 14 线 → Master HDMI 的 640×480 图片闭环，NEXT/PREV 与自动轮播已真板通过。**

## 3. P1-05A 验收结果

### 3.1 功能目标 — PASS

真实 internal SDRAM 存放完整 640×480 RGB888 固定帧，经 APUG011 读回、CDC、整行预取、ping-pong line buffer 后，通过 P1-04C HDMI boundary 输出。

TD6.2.1 bitstream 重新上板后稳定显示：8 px 白边、红/绿/蓝/黄四象限、中央洋红竖条、中央青色横条；无移动黑线、无可见抖动、抽搐或撕裂。

### 3.2 Questa — PASS

```text
p1_framebuffer_pattern_writer      PASS(259)
p1_sdram_read_cdc_bridge           PASS(13)
hdmi_framebuffer_scanout           PASS(35)
p1_sdram_hdmi_pipeline             PASS(258)
p1_sdram_cached_adapter            PASS(58)
p1_sdram_hdmi_cached_chain         PASS(260), pixels=256, underflow=0
cached adapter + official APUG011  PASS(24)
```

protected APUG011 compatibility 保持 tCK/tRCD/DQM/readback/protocol health 全部通过；vendor source 自身的已知 Questa warning 不作为项目 RTL fail。

### 3.3 TD5.6.2 — historical PASS

```text
Setup errors = 0
Hold errors  = 0
Setup WNS    = +0.068 ns
Hold WHS     = +0.131 ns
TNS          = 0
BitGen       = PASS
```

| Clock | Min Period | Max Freq | TNS |
|---|---:|---:|---:|
| 25 MHz pixel | 27.015 ns | 37.000 MHz | 0 |
| 150 MHz SDRAM | 6.598 ns | 151.561 MHz | 0 |
| 50 MHz board | 6.770 ns | 147.710 MHz | 0 |
| 125 MHz serial | 7.177 ns | 139.334 MHz | 0 |

**Timing caution：150 MHz closure 只有约 68 ps setup margin。P1-05A 可以标 `[S]`，但后续不能把它当作宽裕的性能余量。任何影响 active design 的修改都需要重新 STA。**

### 3.4 P1-05A TD6.2.1 routed result

P1-05A 的当前工具链基线为 TD6.2.1。2026-09-21 的 `FPGA_Competition_HDMI_Runs/phy_1/final_timing.rpt` 已完成 routed final STA，Top 为 `p1_hx4s20c_sdram_hdmi_top`，coverage `99.17%`：

```text
SWNS +0.599 ns    STNS 0.000 ns
HWNS +0.003 ns    HTNS 0.000 ns
setup/hold violating endpoints: 0 / 0
```

相关 25/150/50/125 MHz 域均为非负 setup/hold 结果；BitGen 已生成 `FPGA_Competition_HDMI_Runs/phy_1/FPGA_Competition_HDMI.bit`，并已重新上板稳定显示。因此当前 TD6.2.1 实现可记为 `[S][B] PASS`。

优化重点保持在两处：production cached-adapter diagnostics compile-out，以及 HDMI reset release phase 调整。当前 SDC 使用 `derive_clocks`，未用 false-path/clock-group 隐藏 150 MHz 同域逻辑；仅对 APUG011 相位相关硬宏边界保留受限例外。

当前实现仍有 3 条 critical warning：两个 `u_internal_sdram` 初始位置未被采用，以及 1 条 `u_sdram_pll/pll_inst.clkc[2] -> SDRAM_CLK` 时钟网使用 local routing resource。它们不构成当前 STA violation，但必须作为实现风险记录。

### 3.5 资源 — ACCEPTED WITH FOLLOW-UP

```text
LUT      7416 / 19600 = 37.84%
REG      2554 / 19600 = 13.03%
BRAM9K     10 / 64    = 15.62%
BRAM32K     0 / 16
DSP         1 / 29     = 3.45%
PLL         2 / 4      = 50.00%
GCLK        2 / 16     = 12.50%
```

资源足以进入 P1-05B，当前 LUT 使用率约 37.84%。line buffer 的 ERAM 映射优化仍可作为后续资源回收手段；在没有资源压力前不破坏已收敛的 P1-05A baseline。

## 4. P1-05B 媒体能力并入双板主线

P1-05B 的 TF/FAT32/BMP、A/B buffer 和 frame-boundary 安全提交仍是必需能力，并最终按主从架构完成。640×480 是双板第一闭环的媒体规格；P1-05A 保留为单板 rollback/display baseline。当前已经通过的 Slave 本地 TF/BMP 显示只算 M2 子门禁，不等价于双板闭环。

- TF card initialization / block read；
- FAT32；
- 24-bit BI_RGB BMP；
- framebuffer_writer；
- A/B framebuffer；
- frame-boundary swap；
- 手动/自动切图。

`p1_media_framebuffer_loader` 的历史模块证据为 `[U] PASS(225)`；此后真实 TF physical reader、FAT32/BMP 与 Slave SDRAM/HDMI 已取得一次板级本地显示 PASS。该本地 PASS 允许表述“Slave 本地 TF 图片显示成功”，但只有真实图片经过板间媒体数据面并由 Master 安全提交后，才能表述“TF 图片经双板输出完成”。

### P1-05B 验收约束

1. 不破坏 P1-05A framebuffer baseline；
2. 新增模块先 `[U]`，再 provider-realistic chain；
3. combined TD 必须重新 0 setup/hold violation；
4. 特别监控 150 MHz WNS，不能接受负裕量；
5. 真板必须完成真实 TF/BMP 图像显示与 frame-boundary swap；
6. 资源变化必须记录 LUT/REG/BRAM/PLL/GCLK。

## 5. 统一开发节点与分辨率策略

```text
M0: P0/P1-05A 已有基线
M1: 双板协议、A/B/C 契约与可视化控制闭环（board gate 已通过）
M2: 双板 640×480 TF/BMP 第一闭环（P1-05B 功能）
M3: 双板 1920×1080 静态图片传输与主板输出
M4: 图片轮播、切换、转场、字幕、UI 和图像参数
M5: HDMI 音频、音画同步、音频可视化
M6: 选题 1.4 扩展、长稳、故障恢复与最终验收
```

1280×720 不再是开发节点。M3 正式门禁是 1920×1080 静态图片的一次完整传输、主板安全提交和 HDMI 输出；像素格式、packet 宽度和缓存方式由 A/B/集成根据容量、加载时间、P&R/STA 和真板结果共同冻结。任何真实 1080p HDMI profile 都必须独立完成时钟、PHY、P&R、STA 和真板验证。

## 5.1 双板目标边界

双板部署采用主从结构：主板负责最终 HDMI 视频/音频时序、UI/OSD、缩放、转场和输出；从板负责 TF/FAT32/BMP、图片预取和图片数据生产。板间控制和图片数据面沿用当前 GPIO/UART/握手实现，M3 重点验证静态图片 packet 的完整性和加载时间；USB 下载口不作为板间 FPGA 通信链路。

1920×1080 HDMI 仍需要独立的 148.5 MHz pixel profile 和 APUG092/PHY 时序闭合。第二块板只能缓解图片存储和预处理压力；单帧约 2,073,600 像素，主板是否使用 RGB888、RGB565 或受保护区域/line buffer，必须在 M3 按资源与加载时间实测决定。

本项目只维护一条从开始到交付的主线：

```text
三人分别长期负责 A/B/C；每个 M 节点中三线并行，节点末尾集成汇合。P1-05A 只作为回退基线，P1-05B 图片能力通过 M2 双板闭环完成。
```

## 6. 后续 Presentation

双板 + 1080p 从 M1 起就是开发主线；随后按 `M2 → M3 → M4 → M5 → M6` 收口。完整 A/B/C 任务与节点依赖见 `docs/08_three_line_integration_flow.md`。P1-05A fixed-pattern rollback 在整个主线中保留。

## 7. 状态等级

| 等级 | 定义 |
|---|---|
| `[U]` | 单模块 Questa PASS |
| `[C-sub]` | 真实模块子链 PASS |
| `[C]` | 阶段端到端 RTL chain PASS |
| `[S]` | TD synthesis + P&R + timing PASS |
| `[B]` | 真板目标功能 PASS |
| `[L]` | 长稳/压力/恢复 PASS |

不得用“代码完成”“SynOpt 成功”“BitGen 成功”跨级替代真实证据。

## 8. Golden boundary 冻结要求

P1-05A rollback baseline 默认禁止改变：HDMI_B pins、50→25/125 MHz HDMI PLL、APUG092/EG PHY、reset/EDID/IIC divider、640×480 timing，以及已证明的 cached-adapter/CDC/prefetch/scanout 行为。双板 1080p 使用独立 profile/top 和约束；若修改 frozen baseline，必须重新取得对应 Questa、STA 和 board 证据。

## 8. 2026-10-01 路线修订：1080p 直达 + 分板验证门禁

最终目标收敛为：两块 HX4S20C、1920×1080 图片、HDMI 音频、OSD/字幕、转场、缩放、亮度/对比度等实时参数和音频可视化。不做视频输出，不再设置 720p 或持续视频吞吐节点；M3 完成 1080P 静态图片闭环，M4～M6 完成呈现、音频和最终真板验收。

从 M1 起，每个节点必须先做 Master-alone 与 Slave-alone，再接控制链路，最后接图片数据链路。M1 的可视化工程是控制面门禁；M2 已回到最终架构并取得 Master HDMI 图片输出真板 PASS。后续所有节点都以 Master 为最终显示 owner，Slave 只负责图片生产。
