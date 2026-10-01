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

`docs/01~04` 是四份权威文档；`docs/05~08` 是三线计划与集成流程。M1ABC 验证、M2 入口计划以及所有阶段调试/候选实现/复盘统一放在 `docs/develop_records/`；`docs/olds/` 只读。

双板重构后的计划仍以 `docs/01~04` 为架构、目标和状态权威，以 `docs/05~08` 为执行计划。双板、1080p 和板间链路属于主交付计划，除非取得对应 `[C]`、`[S]`、`[B]` 证据，不得写成已实现能力。

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
| HX4S20C board | `[B]` | TD6.2.1 bitstream 已重新上板，framebuffer 稳定显示，无可见撕裂/抖动/移动黑线 |

因此，当前证据应写为：

```text
P1-05A TD6.2.1 [S] PASS
P1-05A TD6.2.1 [B] PASS
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

TD6.2.1 bitstream 已重新上板复测：白边、四象限、洋红竖条和青色横条均稳定显示，未观察到抖动、抽搐、撕裂或移动黑线。

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

## 6. 当前主线：M1 → M2（P1-05B 双板第一闭环）

目标：从板 TF/FAT32/BMP → media service → 板间 packet → 主板 buffer/HDMI，完成 P1-05B 图片能力并恢复安全的 A/B/frame-boundary 提交。

P1-05B 的独立功能开发和 active top 集成进入条件已经满足；P1-05B 第一原则是**复用并保护已完成真板复测的 P1-05A display baseline**，先验证 TF/BMP 写入，不再次修改 HDMI low-level bring-up。

### 6.0 双板与 1.4 计划状态

```text
主板 M：HDMI/APUG092、最终 raster、UI/OSD、缩放、转场、音频
从板 S：TF/FAT32/BMP、vseq/视频预取、媒体缓存、帧/行/tile 生产
```

当前仓库已收敛为两个长期 TD6.2.1 工程：`FPGA_Competition_HDMI_MASTER.al` 与 `FPGA_Competition_HDMI_SLAVE.al`。两者共享唯一 `src/` RTL tree，并分别只加载 `constraints/master/`、`constraints/slave/`；P1-05A rollback 只保留源码与历史证据，不再保留第三个 `.al`。当前 M1 Master Top 为 `m1abc_master_control_top`，Slave Top 为 `m1abc_slave_hdmi_top`；M2~M6 继续演进这两个工程，不新建阶段性 active 工程。双板媒体数据面和真实 1080p HDMI profile 尚未接入最终主线。M1 最小控制面已完成独立两板验证：50 MHz、115200/8N1 GPIO UART，帧为 `0x55 0xA5 opcode length payload crc8`。QuestaSim 10.7c 的四 opcode 循环得到 `masks=1111/1111`、无协议错误；两块 HX4S20C 分别生成 bitstream 并上板后，双向 ACK/link LED 正常。正确物理映射已由真板确认：FPGA `J13` 是本板 TX、经 J1-8 引出；FPGA `F13` 是本板 RX、经 J1-4 引出；两板 J1-12 共地。该结果记作 **M1-B0 UART 控制链 `[B] PASS`**；对应 timing 数值尚需随本轮 M1ABC 工程一起归档，不能用“BitGen 成功”代替完整 `[S]` 记录。

`M1ABC-v5` 已完成真板可视化闭环：A 线 `m1a_uart_service_bridge` 把已验证 UART transport 接到 media-service contract；B 线提供 payload control frame、line packet/sequence/CRC16/PRBS/CDC 合同；C 线提供 coordinator、frame-boundary config CDC 与可视 pattern compositor。Master 的自动轮播以及 KEY2/KEY3/KEY4 能稳定改变 Slave 在 P1-04C 640×480 HDMI_B 上的 4 个 deterministic 页面，link/fault 视觉标记与 LED 状态均符合预期，因此记 **M1ABC board `[B] PASS`**。两个角色 TD6.2.1 工程均可综合并生成可上板 bitstream；M1ABC aggregate Questa 已再次得到 `Errors: 0, Warnings: 0`。最终 STA 报告尚未在本记录中归档，因此不把“BitGen 成功”自动升级成 `[S]`。

两块 HX4S20C 的低速双向控制链已经真板验证；尚未验证的是 **source-synchronous 高速媒体数据面**。两块板之间继续按 40-pin DC3 GPIO 自定义连接规划：正式控制面候选为 SPI，媒体数据面为 source-synchronous GPIO；原理图未提供专用板间 SPI/高速串行接口。板载 USB 不能直接作为两 FPGA 之间的 USB 通道；USB-UART 适合连接电脑观察日志。当前只有杜邦线，因此 M1 先用三根 GPIO 杜邦线完成低速 UART `TX→RX/RX→TX/GND` 握手，之后再评审 SPI 和并行数据 pin map。千兆 Ethernet 暂作为调试/文件搬运后备，不作为首版原始 1080P60 数据面。

M1 最小 UART 门禁与 M1ABC 双板可视化门禁均已实际通过。低速 UART 仍只承担控制面，不传媒体数据；高速 source-synchronous 媒体数据面的真板 PRBS/CRC/sequence 门禁现在成为 **M2-B0**，必须在真实媒体 packet 进入前完成。当前工作位置正式切换到 M2，详见 `docs/08_three_line_integration_flow.md`、`docs/develop_records/M1ABC_V5_VALIDATION.md` 与 `docs/develop_records/M2_REAL_MEDIA_ENTRY.md`。

双板必须生成并单独验证两个 bitstream：`master_top + master ADC/SDC -> master.bit`，`slave_top + slave ADC/SDC -> slave.bit`。每次更换 Top、角色约束、板间 pin map 或时钟参数，都必须分别重新 synthesis、P&R、STA、BitGen；不得复制或混用另一角色的实现结果。

### M1 closeout 与当前节点 M2

M1 的公共边界沿用并扩展已冻结契约：C 线在主板只通过 `media_cmd_valid/ready/image_id/mode` 表达用户媒体意图；A 线是唯一 `p1_media_framebuffer_loader` writer；B 线拥有写入 fence、`writer_done/writer_ok`、front/back metadata 与 `frame_boundary` swap。C 线不得直接驱动 loader、SDRAM、framebuffer base 或板间 GPIO。双板 SPI 控制面、source-synchronous GPIO 数据面、descriptor/packet、credit、CRC 和 CDC 也必须在 M1 冻结。

需要特别区分两种依赖：C 的按键/旋钮/菜单/OSD/转场状态机可用 deterministic raster 和固定 catalog mock 开发；C 的真实选图范围、媒体类型、播放完成/错误必须消费 A 的 `catalog/descriptor/status`，C 的真实缩放、OSD 合成和转场验收必须消费 B 的 `canonical raster/frame_boundary/underflow`。M2 起，mock 只能作为回归源，不能作为双板完成证据。

`src/app/media_command_controller.v` 已完成主板 C 线命令控制器，并由 QuestaSim 10.7c 单元回归验证 `PASS(52)`。它覆盖 `valid/ready` payload 保持、忙碌期间的选图意图合并、播放/暂停、轮播以及本地应急 UI 边界；`key_filter`、`sw_filter`、`menu_fsm`、`app_scenario`、`image_enhance`、`image_scaler`、`osd_overlay`、`transition` 的关联回归亦通过。

2026-09-25 的 TD6.2.1 完整综合、布局布线和 BitGen 无 error。`FPGA_Competition_HDMI_Runs/phy_1/final_timing.rpt` 对 `p1_hx4s20c_sdram_hdmi_top` 报告 STA coverage `99.17%`、SWNS `+0.599 ns`、STNS `0.000 ns`、HWNS `+0.003 ns`、HTNS `0.000 ns`，setup/hold violating endpoints 均为 0；bitstream 生成时间为 2026-09-25 13:53:33。

P1-05A 的实现报告仍只证明冻结 display baseline，不能替代 M1ABC 的角色实现证据。M1ABC 的真板功能门禁已经 PASS：Master 控制、Slave HDMI 可视页面、自动轮播、KEY2/KEY3/KEY4 与双向链路均正常。上一验证包的 `run_all.bat` 没有在用户环境正常执行，因此 aggregate M1ABC Questa 仍需用本发布包修复后的脚本补跑；两个角色最终 STA 数值也需归档后才能补齐完整 `[C]/[S]`。这些证据缺口不改变已取得的 `[B]`，但文档禁止把其写成 1080p 或高速数据面 PASS。当前开发节点进入 **M2：真实 TF/BMP + 双板媒体第一闭环**。

M1A 从板媒体服务骨架已加入 `src/storage/m1a_*`：SPI Mode 0 字节 ingress、命令 CRC-16/CCITT 解码、provider 异步 FIFO CDC、deterministic catalog/descriptor/credit/mock line source，以及组合 shell。新增 `m1a_fat32_catalog` 将现有 `fat32_scan` 与 catalog table 接通；八个 QuestaSim 10.7c testbench 全部通过，受控 MBR/BPB/多扇区根目录 sector-stream 用例验证文件 descriptor 中的 cluster/size/FAT 与 data LBA base/SPC。scanner 可遍历根目录首簇内各扇区，但尚未跟随 FAT 链读取后续目录簇，真实 TF/SPI provider 也尚未连接。此证据仅为模块/受控 sector-stream `[U]/[C-sub]`；不含 B 线线上 packet sequence/CRC、GPIO 链路或 frame commit，也未进入 TD active top，不能记作 M1 汇合或双板完成。

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

## 7. 2026-10-01 M1 双板控制链与 M1ABC 真板关闭记录

已取得的控制链证据：

```text
9600 8N1 A5/5A minimal link                         [B] PASS
115200 8N1 framed link, CRC8, opcodes 01..04         [C-sub][B] PASS
Questa v4: masks=1111/1111, master_err=0, slave_err=0
```

真板三线固定为：

```text
Master J1-8 / J13 TX -> Slave J1-4 / F13 RX
Slave  J1-8 / J13 TX -> Master J1-4 / F13 RX
J1-12 GND <-> J1-12 GND
```

M1ABC 可视化集成已经真板通过。用户实际观察到：

- Slave-alone 能稳定输出默认页面；
- 双板连接后两板 link 状态正常、fault 熄灭；
- Slave HDMI 页面按约 2 s 自动轮播；
- Master KEY2/KEY3 能前后切页，KEY4 能暂停/恢复；
- 左上 link 标记与页面切换均符合设计；
- activity LED 使用 toggle，肉眼可能表现为闪烁或较暗常亮，这是预期表现。

因此 M1ABC **board gate `[B] PASS`**。该验证使用临时拓扑“Master 控制 -> Slave HDMI”，只用于观察 A/B/C 集成；最终架构仍是 Slave 媒体生产、Master 1080p HDMI 输出。

证据边界仍然严格：

1. 本轮 M1ABC RTL 可以在 TD6.2.1 综合并生成并上板 bitstream，但最终 STA 数值尚未归档到本文件，不自动记 `[S]`；
2. 上一验证包 `run_all.bat` 在用户环境未正常执行，本发布包已经重写脚本；aggregate 7 项 M1ABC Questa 需要补跑后再记完整 `[C]`；
3. `hdmi_1080p_raster.v` 只冻结 1920×1080 / 2200×1125 canonical timing，不证明 148.5/742.5 MHz PLL/APUG092/board；
4. M1 UART 只证明控制面，不证明 source-synchronous 高速媒体数据面。

当前进入 M2，下一硬门禁是：**真实 TF/FAT32/BMP 在 Slave 产生 -> 高速/受控数据面 -> Master 端接收/缓存 -> Master HDMI 可视输出**。详见 `docs/develop_records/M2_REAL_MEDIA_ENTRY.md`。
