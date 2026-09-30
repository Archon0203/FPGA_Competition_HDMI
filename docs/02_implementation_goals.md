# 02 · 实现目标与验收边界

## 1. 最终作品目标

在 HX4S20C / EG4S20BG256 上实现无外部 CPU/MCU 的 HDMI 多媒体信息发布终端：

```text
TF/FAT32
  ↓
BMP / frame sequence
  ↓
internal SDRAM framebuffer
  ↓
real-time display pipeline
  ↓
APUG092 HDMI video/audio
  ↓
HDMI display
```

## 2. 当前已成立证据

- P0 media core：`[C] PASS(1698)`；
- P1-02B APUG011 internal SDRAM backend：150 MHz `[S]`；
- P1-04C HDMI_B：`[B] PASS`；
- **P1-05A internal SDRAM framebuffer → HDMI_B：TD6.2.1 routed `[S] PASS`；TD6.2.1 真板 `[B] PASS`。**

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

### 3.4 TD6.2.1 current routed result

当前工具链为 TD6.2.1。2026-09-21 的 `FPGA_Competition_HDMI_Runs/phy_1/final_timing.rpt` 已完成 routed final STA，Top 为 `p1_hx4s20c_sdram_hdmi_top`，coverage `99.17%`：

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

P1-05B 的 TF/FAT32/BMP、A/B buffer 和 frame-boundary 安全提交仍是必需能力，但按最终主从架构直接开发，不要求先完成独立单板闭环再开始双板。640×480 是双板第一闭环的媒体规格；P1-05A 保留为单板 rollback/display baseline。

- TF card initialization / block read；
- FAT32；
- 24-bit BI_RGB BMP；
- framebuffer_writer；
- A/B framebuffer；
- frame-boundary swap；
- 手动/自动切图。

当前第一项子证据：`p1_media_framebuffer_loader` 已 `[U] PASS`。它把 P0 FAT32/BMP/framebuffer writer 连接至 P1 cached APUG011 写后端的抽象接口；fragmented BMP provider-realistic chain 为 `PASS(225)`。该证据不包含真实 TF physical reader CDC、active board top、TD6.2.1 或真板显示。

当前 `p1_media_framebuffer_loader` 仅 `[U] PASS(225)`。只有双板主线中真实 TF 图片经过从板媒体服务和板间数据面，在主板完成安全提交并取得真板证据后，才能对外表述“TF 图片经双板输出完成”。

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
M1: 双板协议、1080p 架构/时钟/引脚契约与开发骨架
M2: 双板 640×480 TF/BMP 第一闭环（P1-05B 功能）
M3: 1280×720 链路 bring-up/debug profile
M4: 双板媒体 + 主板 1920×1080 静态图/UI
M5: 视频、切换、转场、音频
M6: 选题 1.4 扩展与双板 1080p 最终验收
```

1280×720 只用于链路 bring-up，不是最终分辨率，也不作为开启 1080p 设计的长期前置阶段。旧 720p 75/375 MHz candidate 已 STA FAIL，不复用其时钟方案。任何新 profile 都必须独立完成时钟、PHY、P&R、STA 和真板验证。

## 5.1 双板目标边界

双板部署采用主从结构：主板负责最终 HDMI 视频/音频时序、UI/OSD、缩放、转场和输出；从板负责 TF/FAT32/BMP、视频读取、媒体预取和帧/行/tile 数据生产。板间控制使用 SPI，数据面使用待验证的 source-synchronous GPIO 链路；以太网只作为控制、调试或压缩数据后备链路。

1080p60 需要 148.5 MHz pixel clock 和 742.5 MHz serial clock。第二块板只能缓解媒体存储和预处理压力，不能替代输出主板的 APUG092/PHY 时序闭合。1080p 单帧约 2,073,600 个 32-bit word，接近单板 2M×32 SDRAM 容量，因此 1080p 不采用单板 A/B 全帧双缓冲；优先使用从板缓存下一帧、主板行/tile 缓冲和 frame-boundary 提交。

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
