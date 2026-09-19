# 03 · 计划与状态

> **本文件是项目进度和证据状态的唯一权威。** 其他 README 或 develop record 与本文件冲突时，以本文件为准。

## 1. 状态定义

| 标记 | 含义 |
|---|---|
| `[U]` | 单模块 Questa/ModelSim 自检 PASS |
| `[C-sub]` | 真实模块子链 PASS |
| `[C]` | 阶段端到端 RTL chain PASS |
| `[S]` | TD synthesis + P&R + timing 达标 |
| `[B]` | 真板目标功能可观察 PASS |
| `[L]` | 长稳/压力/恢复 PASS |
| `—` | 尚未取得该级证据，不等价于 FAIL |

## 2. 文档维护约束

主要当前文档固定为：

```text
README.md
STRUCTURE.md
docs/01_architecture.md
docs/02_implementation_goals.md
docs/03_plan_and_status.md
docs/04_use_cases.md
```

阶段调试过程、候选实现和复盘允许追加到 `docs/develop_records/`；不要在 `docs/` 根目录新增其它当前设计文档。`docs/olds/` 只读。

## 3. 已收口基础证据

### P0

```text
P0 full media chain [C] PASS(1698)
```

### P1-02B SDRAM

| 项目 | 状态 | 证据 |
|---|---|---|
| `sdram_arbiter` | `[U]` | PASS(39) |
| `sdram_adapter v0.4` | `[U]` | PASS(61) |
| arbiter→adapter | `[C-sub]` | PASS(42) |
| adapter→official APUG011→IS42 | `[C-sub]` | PASS(24) |
| `p1_apug011_bist` | `[U]` | PASS(9) |
| P1-02B TD backend | `[S]` | 150 MHz setup/hold 0 violation |

P1-02B final WNS `+0.059 ns`。

### P1-03/P1-04 HDMI

| 项目 | 状态 | 证据 |
|---|---|---|
| `hdmi_video_adapter` | `[U]` | PASS(24) |
| line-buffer→adapter | `[C-sub]` | PASS(57) |
| test pattern line provider | `[U]` | PASS(37) |
| APUG092 protected behavior sim | TOOL_BLOCKED | protected-region simulator incompatibility |
| P1-04C HDMI_B | `[B]` | 真板稳定八色条 |

P1-04A 720p 75/375 MHz 为历史 STA FAIL；P1-04B 为 TD 可实现但 board 无 HDMI；P1-04C 对齐 official startup 后成为 HDMI golden baseline。

## 4. P1-05A 最终状态 — CLOSED

### 4.1 目标

真实 EG4S20 internal SDRAM 固定 framebuffer → APUG011 → CDC/prefetch/line-buffer → HDMI_B。

### 4.2 最终验证

| 项目 | 状态 | 证据 |
|---|---|---|
| `p1_framebuffer_pattern_writer` | `[U]` | PASS(259) |
| `p1_sdram_read_cdc_bridge` | `[U]` | PASS(13) |
| `hdmi_framebuffer_scanout` | `[U]` | PASS(35) |
| `p1_sdram_hdmi_pipeline` | `[C-sub]` | PASS(258) |
| `p1_sdram_cached_adapter` | `[U]` | PASS(58), reads=8, app_reads=8, hits=6, misses=2 |
| cached provider chain | `[C-sub]` | PASS(260), pixels=256, underflow=0 |
| cached adapter + official APUG011 | `[C-sub]` | PASS(24) |
| combined TD5.6.2 | `[S]` | 0 setup / 0 hold, WNS +0.068 ns, WHS +0.131 ns |
| final BitGen + HX4S20C board | `[B]` | 完整 framebuffer 稳定显示，无可见撕裂/抖动/移动黑线 |

因此：

```text
P1-05A [S] PASS
P1-05A [B] PASS
P1-05A CLOSED
```

未取得 `[L]`，所以暂不声称长时间压力/掉电恢复等级。

### 4.3 Final TD timing

```text
STA coverage      98.69%
Setup errors      0
Hold errors       0
Setup WNS        +0.068 ns
Setup TNS         0.000 ns
Hold WHS         +0.131 ns
Hold TNS          0.000 ns
```

| Clock | Target | Min Period | Max Freq | TNS |
|---|---:|---:|---:|---:|
| `u_hdmi_pll/u_pll.clkc[0]` | 25 MHz | 27.015 ns | 37.000 MHz | 0 |
| `u_sdram_pll/pll_inst.clkc[1]` | 150 MHz | 6.598 ns | 151.561 MHz | 0 |
| `hx4s20c_clk50m` | 50 MHz | 6.770 ns | 147.710 MHz | 0 |
| `u_hdmi_pll/u_pll.clkc[1]` | 125 MHz | 7.177 ns | 139.334 MHz | 0 |

**Timing caveat：整体 setup margin 仅 +0.068 ns。P1-05A 是“timing clean”，不是“timing 宽裕”。后续每次影响 active netlist 的修改必须重新 STA。**

### 4.3A TD6.2.1 migration / timing optimization — OPEN

官方要求已将工具链切换至 TD6.2.1。2026-09-17 对当前 P1-05A source baseline 做了 TD6.2.1 完整实现，旧网表 routed report 为：

```text
STA coverage 99.15%
SWNS         -7.098 ns
HWNS         +0.011 ns
150 MHz SWNS -1.119 ns
150 MHz HWNS +0.182 ns
post-place LUT 7437 / 19600
```

其中 `-7.098 ns` 的 worst path 是 APUG011/internal SDRAM hard-I/O 的 `clk2 -> clk1` setup analysis；`150 MHz self-domain` 的软件时序负裕量主要落在 `p1_sdram_cached_adapter` 的 runtime diagnostic cone。硬件 routed timing 仍为正，但整体 margin 偏薄。

当前 source tree 的优化 candidate：

- production `p1_sdram_cached_adapter` 使用 `.ENABLE_RUNTIME_DIAGNOSTICS(0)`，将非数据通路的 debug counters / redundant assertions 从 150 MHz active cone 中剔除；默认参数仍为 `1`，因此现有 Questa 单测/集成 TB 不改变。
- HDMI reset release 使用官方例程的 50 MHz rising edge；下降沿实验缩短了 125 MHz serial-domain recovery window，已恢复上升沿实现，功能时序仍保持约 20 ms reset hold。

**重新取得 `[S]` 的必要条件：** 使用 TD6.2.1 从 `read_design → synthesis → P&R → final STA` 完整重跑；确认 25/150/50/125 MHz 均无 setup/hold violation 后，才更新本节和最终 timing evidence。BitGen/真板重新验证后才能恢复当前工具链下的 `[B]` 结论。

### 4.4 Final post-Phy resource

```text
LUT      9977 / 19600 = 50.90%
REG      2825 / 19600 = 14.41%
LE      10440
DSP         1 / 29
BRAM9K     10 / 64    = 15.62%
BRAM32K     0 / 16
PLL         2 / 4
GCLK        2 / 16
IO          7
```

资源风险：LUT 已使用约一半；line-buffer ERAM 化仍是候选优化项，但不在 P1-05A closeout 后立即重构。

### 4.5 Board result

最终画面：白色边框 + 红/绿/蓝/黄四象限 + 洋红竖条 + 青色横条，同时稳定存在。之前的三类 bring-up failure 已全部解决：

```text
八色 fallback     -> framebuffer 未进入显示
全屏洋红          -> startup/prefetch protocol diagnostic
移动彩色窄线      -> sustained provider bandwidth underflow
```

最终 bitstream 上板后未观察到抖动、抽搐、撕裂或移动黑线。

详细实现与调试过程见：`docs/develop_records/P1-05A_CLOSEOUT_20260912.md`。

## 5. P1-05A 冻结事项

默认冻结：

- P1-04C HDMI_B pin/PLL/APUG092/PHY/reset/EDID；
- 25↔150 MHz CDC 结构和 asynchronous clock-group SDC；
- cached-adapter read cache；
- registered write request slice；
- `lb_fill_ready` prefetch scheduling invariant；
- framebuffer scanout cadence。

修改上述任一项，必须重新取得对应 lower-level regression、combined STA 和 board 证据。

## 6. 下一阶段 P1-05B

目标：TF/FAT32/BMP → SDRAM framebuffer → HDMI，恢复 A/B framebuffer 与 frame-boundary swap。

进入条件已经满足。P1-05B 第一原则是**复用并保护 P1-05A display baseline**，先验证 TF/BMP 写入，不再次修改 HDMI low-level bring-up。
