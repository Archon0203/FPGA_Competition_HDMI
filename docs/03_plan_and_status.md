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

主要当前文档包括：

```text
README.md
STRUCTURE.md
docs/01_architecture.md
docs/02_implementation_goals.md
docs/03_plan_and_status.md
docs/04_use_cases.md
docs/05_line_A_media_plan.md
docs/06_line_B_framebuffer_plan.md
docs/07_line_C_presentation_plan.md
docs/08_three_line_integration_flow.md
```

`docs/01~04` 是四份权威文档；`docs/05~08` 是并列的三线计划与集成流程文档。阶段调试过程、候选实现和复盘追加到 `docs/develop_records/`；`docs/olds/` 只读。

双板重构后的计划仍以 `docs/01~04` 为架构、目标和状态权威，以 `docs/05~08` 为执行计划。双板、1080p 和板间链路属于计划/feasibility，除非取得对应 `[C]`、`[S]`、`[B]` 证据，不得写成已实现能力。

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

## 4. P1-05A 状态

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
| combined TD5.6.2 | `[S]` | 历史 closeout：0 setup / 0 hold, WNS +0.068 ns, WHS +0.131 ns |
| TD6.2.1 routed final + BitGen | `[S]` | 2026-09-25 report：0 setup / 0 hold，SWNS +0.599 ns，HWNS +0.003 ns；bitstream 已生成 |
| HX4S20C board | `[B]` | 历史 framebuffer 稳定显示，无可见撕裂/抖动/移动黑线；TD6.2.1 bitstream 尚待复测 |

因此，当前证据应写为：

```text
P1-05A TD6.2.1 [S] PASS
P1-05A historical [B] PASS
P1-05A TD6.2.1 board re-test pending
```

未取得 `[L]`，所以暂不声称长时间压力/掉电恢复等级。

### 4.3 TD6.2.1 final timing

```text
Generated         2026-09-25 13:53:29
STA coverage      99.17%
Setup violations  0
Hold violations   0
SWNS              +0.599 ns
STNS              0.000 ns
HWNS              +0.003 ns
HTNS              0.000 ns
```

| Clock | Target | R-Period | R-Freq | SWNS / HWNS |
|---|---:|---:|---:|---:|
| `u_hdmi_pll/u_pll.clkc[0]` | 25 MHz | 21.022 ns | 47.569 MHz | +9.489 / +0.003 ns |
| `u_sdram_pll/pll_inst.clkc[1]` | 150.015 MHz | 5.914 ns | 169.090 MHz | +0.752 / +0.067 ns |
| `hx4s20c_clk50m` | 50 MHz | 9.784 ns | 102.208 MHz | +10.216 / +0.648 ns |
| `u_hdmi_pll/u_pll.clkc[1]` | 125 MHz | 6.802 ns | 147.016 MHz | +0.599 / +0.285 ns |

**Timing caveat：当前硬件最小 hold 裕量为 +0.003 ns（3 ps）。P1-05A 是“当前 routed STA 无违例”，不是“时序裕量宽裕”。后续每次影响 active netlist 的修改必须重新 STA。**

### 4.3A TD6.2.1 实现记录与 warning

官方要求已将工具链切换至 TD6.2.1。此前 2026-09-17 的负 SWNS 是预优化历史结果：

```text
STA coverage 99.15%
SWNS         -7.098 ns
HWNS         +0.011 ns
150 MHz SWNS -1.119 ns
150 MHz HWNS +0.182 ns
post-place LUT 7437 / 19600
```

其中 `-7.098 ns` 和 `-1.119 ns` 只用于说明优化前问题，不代表当前 2026-09-25 routed result。

当前 source tree 已采用的优化：

- production `p1_sdram_cached_adapter` 使用 `.ENABLE_RUNTIME_DIAGNOSTICS(0)`，将非数据通路的 debug counters / redundant assertions 从 150 MHz active cone 中剔除；默认参数仍为 `1`，因此现有 Questa 单测/集成 TB 不改变。
- HDMI reset release 使用官方例程的 50 MHz rising edge；下降沿实验缩短了 125 MHz serial-domain recovery window，已恢复上升沿实现，功能时序仍保持约 20 ms reset hold。

当前 TD6.2.1 已完成 `read_design → synthesis → P&R → final STA → BitGen`，并满足 `[S]`。但以下 warning 仍须保留在风险清单中：

1. `u_internal_sdram` 的两个初始 location `(12, 12)`、`(164, 288)` 未被采用，ECO placement 移动了实例；
2. 1 条时钟网使用 local routing resource，目标为 `u_sdram_pll/pll_inst.clkc[2] -> SDRAM_CLK`。

这些 warning 当前没有形成 final STA violation；后续若修改 ADC/布局约束或时钟资源，必须重新生成 report 并重新评估。

### 4.4 Current post-route resource

```text
LUT      7416 / 19600 = 37.84%
REG      2554 / 19600 = 13.03%
LE       7891
DSP         1 / 29    = 3.45%
BRAM9K     10 / 64    = 15.62%
BRAM32K     0 / 16
PLL         2 / 4     = 50.00%
GCLK        2 / 16    = 12.50%
IO          7 / 188   = 3.72%
```

TD5.6.2 historical closeout 的 LUT/REG `9977/2825` 不用于描述当前 TD6.2.1 routed netlist。当前 LUT 约 37.84%，但 local clock routing warning 和 3 ps hold 裕量仍是实现风险。

### 4.5 Board result

最终画面：白色边框 + 红/绿/蓝/黄四象限 + 洋红竖条 + 青色横条，同时稳定存在。之前的三类 bring-up failure 已全部解决：

```text
八色 fallback     -> framebuffer 未进入显示
全屏洋红          -> startup/prefetch protocol diagnostic
移动彩色窄线      -> sustained provider bandwidth underflow
```

历史 bitstream 上板后未观察到抖动、抽搐、撕裂或移动黑线；本次 TD6.2.1 bitstream 尚无新的上板观察记录。

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

P1-05B 的独立功能开发进入条件已经满足；active top 集成仍须先完成 TD6.2.1 bitstream 的 P1-05A 真板复测。P1-05B 第一原则是**复用并保护 P1-05A display baseline**，先验证 TF/BMP 写入，不再次修改 HDMI low-level bring-up。

### 6.0 双板与 1.4 计划状态

```text
主板 M：HDMI/APUG092、最终 raster、UI/OSD、缩放、转场、音频
从板 S：TF/FAT32/BMP、vseq/视频预取、媒体缓存、帧/行/tile 生产
```

当前工程没有板间通信端口、双板 top、source-synchronous GPIO 约束或双板证据。SPI 控制平面、GPIO 数据平面、1080p HDMI profile 均为未开始的计划项。1.4 扩展虽已列入项目目标，状态仍为待整合。

### P1-05B-00 I0 契约冻结，进入 I1

I0 的公共边界现已冻结：C 线在主板只通过 `media_cmd_valid/ready/image_id/mode` 表达用户媒体意图；A 线是唯一 `p1_media_framebuffer_loader` writer；B 线拥有写入 fence、`writer_done/writer_ok`、front/back metadata 与 `frame_boundary` swap。C 线不得直接驱动 loader、SDRAM、framebuffer base 或板间 GPIO。

`src/app/media_command_controller.v` 已完成主板 C 线 I0 命令控制器，并由 QuestaSim 10.7c 单元回归验证 `PASS(52)`。它覆盖 `valid/ready` payload 保持、忙碌期间的选图意图合并、播放/暂停、轮播以及本地应急 UI 边界；`key_filter`、`sw_filter`、`menu_fsm`、`app_scenario`、`image_enhance`、`image_scaler`、`osd_overlay`、`transition` 的关联 C0 回归亦通过。

2026-09-25 的 TD6.2.1 完整综合、布局布线和 BitGen 无 error。`FPGA_Competition_HDMI_Runs/phy_1/final_timing.rpt` 对 `p1_hx4s20c_sdram_hdmi_top` 报告 STA coverage `99.17%`、SWNS `+0.599 ns`、STNS `0.000 ns`、HWNS `+0.003 ns`、HTNS `0.000 ns`，setup/hold violating endpoints 均为 0；bitstream 生成时间为 2026-09-25 13:53:33。

该实现报告的 active top 尚未列入 `media_command_controller`，因此它证明的是冻结 P1-05A display baseline 的 TD 实现状态，不能替代新增 C 控制器的独立 Questa 证据，也不能宣称 P1-05B 已完成。I0 在“公共契约冻结”意义上结束；A loader -> B sink/manager 的真实写事务桥、一次 `start/done`、write fence 和 `pending_swap` 仍未取得端到端集成 PASS。当前主线进入 I1。

### P1-05B-01 写入侧媒体 loader — `[U] PASS`

`p1_media_framebuffer_loader` 已将冻结的 P0 `fat32_file_reader -> bmp_parser/bmp_pixel_stream -> framebuffer_writer` 封装为 P1 150 MHz abstract SDRAM write source，并通过：

```text
fragmented FAT32 sector provider
 -> p1_media_framebuffer_loader
 -> sdram_arbiter
 -> p1_sdram_cached_adapter
 -> mock APUG011 application port
```

ModelSim 10.6d：

```text
PASS: p1_media_framebuffer_loader fragmented BMP -> cached APUG011 chain
checks=225, app_writes=816
```

测试覆盖 17×12、24-bit BI_RGB、BGR/bottom-up、每行 1-byte padding、`data_offset=54` 与 FAT cluster `3 -> 7 -> EOC`，并检查每一个 provider memory word 的独立 RGB golden。P0 full chain 亦回归 `PASS(1698)`；cached adapter 单测回归 `PASS(58)`。

此项仅为 `[U]`：当前 loader 未接入 active board top；真实 TF physical reader 到 150 MHz write domain 的 CDC/provider wrapper、640×480 真 BMP 写入、A/B frame swap、P1-05B active top 的 combined TD6.2.1 STA 及 board evidence 均未完成。当前 TD6.2.1 report 对应 P1-05A active top，不能作为 P1-05B 的实现证据。不得据此宣称 P1-05B 或 TF→HDMI 已完成。
