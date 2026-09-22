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
- **P1-05A internal SDRAM framebuffer → HDMI_B：TD6.2.1 routed `[S] PASS`；历史真板 `[B] PASS`。**

## 3. P1-05A 验收结果

### 3.1 功能目标 — PASS

真实 internal SDRAM 存放完整 640×480 RGB888 固定帧，经 APUG011 读回、CDC、整行预取、ping-pong line buffer 后，通过 P1-04C HDMI boundary 输出。

历史真板验证稳定显示：8 px 白边、红/绿/蓝/黄四象限、中央洋红竖条、中央青色横条；无移动黑线、无可见抖动、抽搐或撕裂。该 `[B]` 证据对应历史 P1-05A bitstream，不代表本次 TD6.2.1 bitstream 已完成板级复测。

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

相关 25/150/50/125 MHz 域均为非负 setup/hold 结果；BitGen 已生成 `FPGA_Competition_HDMI_Runs/phy_1/FPGA_Competition_HDMI.bit`。因此当前 TD6.2.1 实现可记为 `[S] PASS`。这不等价于新工具链的 `[B]`：当前文档仍只拥有历史 P1-05A 真板 framebuffer 证据，TD6.2.1 bitstream 尚待重新下载和观察。

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

## 4. 下一目标：P1-05B TF/BMP

P1-05B 在 P1-05A display path 不变的前提下加入：

- TF card initialization / block read；
- FAT32；
- 24-bit BI_RGB BMP；
- framebuffer_writer；
- A/B framebuffer；
- frame-boundary swap；
- 手动/自动切图。

当前第一项子证据：`p1_media_framebuffer_loader` 已 `[U] PASS`。它把 P0 FAT32/BMP/framebuffer writer 连接至 P1 cached APUG011 写后端的抽象接口；fragmented BMP provider-realistic chain 为 `PASS(225)`。该证据不包含真实 TF physical reader CDC、active board top、TD6.2.1 或真板显示。

只有 P1-05B 真板通过后，才能对外表述“TF→SDRAM→HDMI 基础图片播放完成”。

### P1-05B 验收约束

1. 不破坏 P1-05A framebuffer baseline；
2. 新增模块先 `[U]`，再 provider-realistic chain；
3. combined TD 必须重新 0 setup/hold violation；
4. 特别监控 150 MHz WNS，不能接受负裕量；
5. 真板必须完成真实 TF/BMP 图像显示与 frame-boundary swap；
6. 资源变化必须记录 LUT/REG/BRAM/PLL/GCLK。

## 5. 分辨率演进

```text
640×480 : P1-05A stable baseline
1280×720: 独立 timing optimization
1920×1080 / 双板: P4 feasibility
```

720p 旧 75/375 MHz candidate 已 STA FAIL，不与当前 640×480 baseline 混用。

## 6. 后续 Presentation

P1-05B `[B]` 后再推进：OSD/字幕、转场、亮度/对比度、HDMI audio、音频可视化、应急画面。

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

P1-05B 默认禁止改变：HDMI_B pins、50→25/125 MHz HDMI PLL、APUG092/EG PHY、reset/EDID/IIC divider、640×480 timing，以及 P1-05A 已证明的 cached-adapter/CDC/prefetch/scanout 行为。若必须修改，必须说明原因并重新取得对应 Questa、STA 和 board 证据。
