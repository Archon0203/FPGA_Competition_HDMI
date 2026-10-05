# 03 · 计划与状态

> **本文件是项目进度、证据等级和“当前是否通过”的唯一权威。** 其他 README、三线计划或 `docs/develop_records/` 中的阶段记录若与本文冲突，以本文为准。开发记录可以保留当时的判断，但不得覆盖这里的当前状态。

## 1. 状态定义

| 标记 | 含义 |
|---|---|
| `[U]` | 单模块 Questa/ModelSim 自检 PASS |
| `[C-sub]` | 真实模块子链 PASS |
| `[C]` | 阶段端到端 RTL chain PASS |
| `[S]` | 对**对应 active candidate** 完成 TD synthesis + P&R + final STA，setup/hold 达标 |
| `[B]` | 对**对应 active candidate** 完成真板目标功能 PASS |
| `[L]` | 长稳/压力/恢复 PASS |
| `—` | 尚未取得该级证据；不等价于 FAIL |
| `未通过` | 已有明确反例或板级现象，当前候选不能作为通过版本 |

证据不得跨候选继承。旧版本的 `[S]` 或 `[B]` 可以继续证明旧基线，但不能自动给后续修改后的 RTL/bitstream 升级状态。

## 2. 文档权威与目录纪律

`docs/` 根目录只保留以下 8 份规范文档：

```text
docs/01_architecture.md
docs/02_implementation_goals.md
docs/03_plan_and_status.md
docs/04_use_cases.md
docs/05_line_A_media_plan.md
docs/06_line_B_framebuffer_plan.md
docs/07_line_C_presentation_plan.md
docs/08_three_line_integration_flow.md
```

职责固定为：

- `01`：系统架构与最终职责边界；
- `02`：目标与证据门槛；
- `03`：唯一进度/证据状态权威；
- `04`：场景与演示口径；
- `05~07`：A/B/C 三线计划；
- `08`：M0~M6 统一路线。

开发过程、验证步骤、候选说明、复盘、日志和截图统一放入 `docs/develop_records/`；原始证据统一放入 `docs/develop_records/evidence/`；历史方案放入 `docs/olds/` 或 `docs/develop_records/`，且不得改写本文的当前状态。

两个指定的阶段入口记录是：

```text
docs/develop_records/M1ABC_V5_VALIDATION.md
docs/develop_records/M2_REAL_MEDIA_ENTRY.md
```

## 3. 已关闭基线

### 3.1 P0 Media Core

```text
P0 full media chain [C] PASS(1698)
```

该证据继续作为文件流、BMP、framebuffer 抽象链的 RTL 基线。

### 3.2 P1-02B SDRAM backend

| 项目 | 状态 | 证据摘要 |
|---|---|---|
| `sdram_arbiter` | `[U]` | PASS(39) |
| `sdram_adapter v0.4` | `[U]` | PASS(61) |
| arbiter→adapter | `[C-sub]` | PASS(42) |
| adapter→official APUG011→IS42 | `[C-sub]` | PASS(24) |
| P1-02B TD backend | `[S]` | 150 MHz setup/hold 0 violation |

### 3.3 P1-04C HDMI baseline

`P1-04C HDMI_B` 已取得 `[B] PASS`，作为 HDMI rollback/golden boundary。P1-04A 720p candidate 的历史 STA FAIL 不用于描述当前能力。

### 3.4 P1-05A internal SDRAM framebuffer baseline

P1-05A 640×480 internal SDRAM framebuffer → HDMI_B 已关闭：

```text
TD6.2.1 routed [S] PASS
SWNS +0.599 ns
STNS 0.000 ns
HWNS +0.003 ns
HTNS 0.000 ns

HX4S20C board [B] PASS
```

这是冻结的 rollback baseline。3 ps hold 裕量很小，因此只能表述为“该 routed 实现无违例”，不能表述为“时序裕量充足”。

## 4. M1 双板控制基线

M1ABC 使用临时拓扑“Master 控制 → Slave HDMI deterministic 页面”验证控制平面，不代表最终媒体数据面。

已取得：

```text
115200 8N1 framed UART + CRC8              [C-sub][B] PASS
M1ABC aggregate QuestaSim 10.7c            [C] PASS
Master KEY2/KEY3/KEY4 控制 Slave 页面       [B] PASS
```

M1 的 `[B]` 只证明低速三线 UART 控制、角色 bitstream 和 mock/deterministic media-service 可视闭环。它**不证明**真实 TF 图片切换、source-synchronous 高速数据面或 1080p。

M1 关闭记录以 `docs/develop_records/M1ABC_V5_VALIDATION.md` 为准。

## 5. 当前节点：M2

M2 的完整目标仍是：

```text
Slave TF/FAT32/BMP
  -> media service
  -> inter-board media data plane
  -> Master RX/buffer/safe commit
  -> Master HDMI
```

M2 **基础双板图片闭环已取得真板 `[B] PASS`，但节点尚未完全关闭**。2026-10-05 FIX6 修正 `link_data[3:5]` 的 J1/FPGA 球位映射后，用户重新构建并上板确认：Slave 从 TF 读取真实 640×480 BMP，经 14 线链路传到 Master，Master HDMI 能显示图片，NEXT/PREV 可切换，自动轮播可工作。当前版本冻结为 `M2_FIX6_BOARD_PASS_20261005`。仍未关闭的内容包括加载时延、Loading UI 形态、故障/复位长稳，以及后续持续视频所需的高速数据面。

### 5.1 已通过：Slave 本地真实 TF/BMP 第一图

2026-10-03，修正 `sd_reader.v` 中 CMD17 command 尾字节的 end bit（`8'h00 -> 8'h01`）后，真板首次稳定显示 TF 卡内 640×480 BMP：

```text
TF -> SPI SD -> FAT32/catalog -> BMP
   -> Slave SDRAM -> Slave 640×480 HDMI
```

板级现象：插卡并复位后先出现黄色加载页，随后出现真实 BMP；无卡复位进入红色 fault，重新插卡并复位可恢复。

因此只记：

```text
M2-A local TF/BMP -> Slave HDMI [B] PASS
```

该 `[B]` 不等价于 M2 双板 `[B]`，也不证明多图切换/轮播已经通过。

### 5.2 M2 时序与资源证据边界

已归档的一次 M2 Slave routed 实现报告（早于 DIAG5/CMD17 修复和后续双板控制修改）为：

```text
SWNS +0.659 ns
STNS 0.000 ns
HWNS +0.014 ns
HTNS 0.000 ns
```

同一阶段的 area 记录为：

```text
LUT      13133 / 19600 = 67.01%
REG       7227 / 19600 = 36.87%
BRAM9K      10 / 64
BRAM32K       0 / 16
```

这组报告只证明当时对应 netlist 的实现状态，**不能作为 DIAG5、DUALCTRL、DUALCTRL2 或 FIX1 的 `[S]` 证据**。FIX1 未单独取得这些证据；本轮新候选的结果见下表。

资源分析记录显示 `line_buffer_pingpong` 是显著 LUT 消耗项；但资源优化属于后续任务，不能与当前控制正确性证据混写。本轮控制修复没有开展 LUT/BRAM 资源重构。

2026-10-04 新候选 `M2_CONTROL_RELOAD_FIX_20261004` 已完成两角色 synthesis → P&R → final STA → BitGen：

| Top | SWNS | HWNS | STNS / HTNS | STA coverage |
|---|---|---|---|---|
| `m1abc_master_control_top` | +8.695 ns | +0.223 ns | 0 / 0 ns | 97.96% |
| `m2_slave_tf_hdmi_top` | +0.570 ns | +0.014 ns | 0 / 0 ns | 99.52% |

此 `[S]` 仅对应当前 UART 控制 + Slave 本地 HDMI 候选及现有约束，不代表尚未完成的双板媒体数据面或 1080p。报告、源码/bitstream SHA256 见 [本轮记录](develop_records/M2_CONTROL_RELOAD_FIX_20261004.md)。

### 5.3 已通过的旧拓扑：Master 控制 Slave 图片切换/轮播

第一次把 M1 控制接到真实 TF 媒体后，板上出现：

- 自动播放约每几秒使画面闪/抖一次，但通常仍显示原图；
- NEXT/PREV 多数只能造成画面扰动，不能稳定切换；
- 取出 TF、等待、重新插卡后，按键曾能成功切换一次。

以上为首次候选的历史失败。2026-10-04 用户随后明确确认：`M2_CONTROL_RELOAD_FIX_20261004` 轮播和切换完全正常，因此该候选的 real-media NEXT/PREV、PLAY/PAUSE + carousel、Dual-control 记 `[B] PASS`；尚无长稳或完整断链恢复验收。

后续代码审查提出 `OPEN -> ACCEPTED` 被 Master 过早视为“整图完成”的问题，并形成 `OPEN -> ACCEPTED -> STATUS polling -> DONE` 的 DUALCTRL2 候选；但该候选首次综合又暴露 `source_valid` 未声明的接口错误。

FIX1 是历史接口修补候选，未单独取得板级证据。上一已板测候选为 `M2_CONTROL_RELOAD_FIX_20261004`：

- 修复连续加载时误消费上一事务的 sticky done/parser 状态；旧 loader 在新多图回归中复现 9 项失败，修复后通过。
- 修复 TD 将前向引用的 dispatcher ready 当成未驱动隐式线的问题。
- 完成语义改为：当前图加载成功、SDRAM fence 完成并在帧边界实际发布后，Slave 才报告匹配图片的 DONE；Master 据此开始完整轮播停留计时。
- 修复排队 OPEN 误报旧 DONE、超时提前解锁、延迟切换意图未取消的问题。

| 当前候选证据 | 状态 |
|---|---|
| 7 项 Questa 单元/子链回归 | `[U/C-sub] PASS` |
| 两角色 final STA + BitGen | `[S] PASS`，现有约束内 setup/hold 0 violation |
| 此候选真板 NEXT/PREV/轮播 | `[B] PASS`，用户确认完全正常，HDMI 位于 Slave |
| 完整双板 TF → Master HDMI | 未完成 |

单缓冲替换期间仍显示加载/诊断页，本轮不宣称无闪屏切换。该候选 HDMI 位于 Slave，已被用户确认通过。原步骤见 [修复与复测记录](develop_records/M2_CONTROL_RELOAD_FIX_20261004.md)。

### 5.4 Slave TD 工程文件问题

协作者从仓库主分支打开 `FPGA_Competition_HDMI_SLAVE.al` 时曾出现 TD6.2.1 “Unable to write the project file / Save As”。对上传仓库快照的比较发现，记录的 `origin/main` Slave 工程文件含 5 个重复 `<File Path=...>` 条目，而用户本机可打开版本无重复。

这属于工程文件维护问题，不属于 M2 媒体功能 PASS。当前候选包使用去重 `.al`，并提供 `tools/check_td_project.py` 做重复路径/CRLF 检查；是否已合并回团队主分支仍由团队 Git 流程确认。

### 5.5 历史候选：14 线 TF → Master HDMI bring-up

2026-10-05 已修复主板控制断点：`m2_master_tf_hdmi_top` 不再使用未连接真实
catalog 的 M1 演示控制 wrapper，改由 `m2_master_media_control` 将主板按键、
真实 UART coordinator、Slave catalog/status 和 OPEN/DONE 完成语义接通。该修改
已通过 ModelSim `vlog` 语法/依赖编译与 TD 工程源文件检查；尚未取得修改后两
bitstream 的 `[S]`/`[B]`，因此双板 TF → Master HDMI 仍保持未验收状态。

`M2_MASTER_OUTPUT_20261004`：Top 为 `m2_master_tf_hdmi_top` 与 `m2_slave_media_tx_top`；两份长期 `.al` 已同步。TF 留 Slave；HDMI、按键、UI、SDRAM 和行缓存位于 Master。14 根线包含 2 UART、7 数据、REQ、ACK、显示发布反馈、2 GND；具体接法只按 [逐针表](develop_records/M2_MASTER_OUTPUT_20261004.md)。

| 项目 | 当前证据 |
|---|---|
| 上一拓扑：Master 控制 Slave 显示 | 用户确认 `[B] PASS` |
| 新拓扑：真实媒体 + 新传输、CRC/背压、加载 UI、RAM/scanout | 12 项 `[U/C-sub] PASS` |
| Master final routed | 4514 LUT；SWNS +0.236 ns，HWNS +0.003 ns；STNS/HTNS=0；BitGen 完成 |
| Slave final routed | 6114 LUT；SWNS +10.085 ns，HWNS +0.075 ns；STNS/HTNS=0；BitGen 完成 |
| TF → 14 线 → Master HDMI 真板 | `—`，待接线、同时更新两 bitstream 后验收 |
| 1080p / 高速持续视频 / 双缓冲无闪屏 | 未完成 |

LUT 降低来自 RAM 推断修正与职责拆分。新链路是有确认的低速图片搬运，不是高速视频吞吐证据。当前卡 SPI 速率保持已验证值，加载耗时未宣称缩短。故障/断线可能需双板复位，M2 安全恢复门槛尚未关闭。

### 5.6 历史集成候选：M2_TEAM_INTEGRATION_20261005

已在 `codex/m2-team-integration-20261005` 集成 main 的 PR #39（A）与 #38（B），清除 TD AutoExcluded，修复 A 测试的 ready 多驱动，并补齐新 Master 控制和原多文件媒体回归。14 项 `[U/C-sub] PASS`。

两角色 final STA/BitGen 完成：Master 4386 LUT，SWNS +0.670 ns、HWNS +0.003 ns；Slave 6114 LUT，SWNS +10.085 ns、HWNS +0.075 ns；STNS/HTNS 均为 0。`[S]` 仅对应本候选与当前约束。`[B]` 待验，旧 10-04 候选报告不能替代这次集成报告。

交付：`sim_work/m2_team_integration_20261005/delivery/master.bit` 与 `slave.bit`。沿用 14 线接法，HDMI 接 Master、TF 留 Slave。[集成内容、证据和板测步骤](develop_records/M2_TEAM_INTEGRATION_20261005.md)。

### 5.7 当前冻结基线：M2_FIX6_BOARD_PASS_20261005

FIX6 对 B 线约束做了原理图级交叉核对，修正 Master/Slave 两侧 `link_data[3:5]`：

```text
J1-5  link_data[3] -> H13
J1-6  link_data[4] -> H14
J1-7  link_data[5] -> J14
```

用户完成重新综合/烧录后取得真板结果：

```text
TF/FAT32/BMP -> Slave -> 14-line transport -> Master framebuffer -> HDMI  [B] PASS
NEXT/PREV                                                               [B] PASS
auto carousel                                                           [B] PASS
```

板上已不再停留于 Loading-only，也不再出现先前蓝屏问题。该结果证明当前 640×480 静态图片双板链路已经闭环。

本次全项目 audit 的关键结果：

- J1 electrical static audit PASS；
- `tb_m2_physical_pin_fault_signature` PASS；
- `tb_m2_full_frame_mailbox_640x480` PASS；
- 但 `framebuf/tb_p1_sdram_cached_adapter` 仍为 current active regression 的已知 FAIL；
- 另有若干历史/可选 testbench FAIL，不能据此宣称全仓 Questa 全绿。

当前已知体验/架构问题：

1. 图片加载明显偏慢，官方样例可近似秒切，本工程当前仍有较长等待；
2. Loading UI 当前整屏覆盖显示，后续应改为保留上一帧，仅叠加小型加载提示；
3. 14 线握手链本阶段只作为静态图片链验证，不作为持续视频链路；
4. 断链、异常卡、复位恢复和长稳仍需单独验收。

冻结记录见 [`develop_records/M2_FIX6_BOARD_PASS_FREEZE_20261005.md`](develop_records/M2_FIX6_BOARD_PASS_FREEZE_20261005.md)。

## 6. M2 关闭门槛

M2 只有同时满足以下条件才可关闭：

1. `[C]`：真实 TF/FAT32/BMP 经完整双板媒体链到 Master 显示可复现；
2. `[S]`：Master/Slave 对应最终 M2 candidate 均完成 TD6.2.1 final STA，setup/hold 0 violation；
3. `[B]`：显示器接 Master HDMI，至少 4 张真实 BMP 可稳定 NEXT/PREV 与自动轮播；
4. `[B]`：断链、错包、坏文件或重置时不提交半帧，能保持上一帧或 fallback；
5. 控制命令必须以真实媒体事务完成为边界，不能把 UART ACK/`ACCEPTED` 当成整帧完成。

当前状态：**基础双板真实图片、手动切换和自动轮播已经通过；M2 完整关闭门槛仍未全部满足。** 当前缺口主要是异常/复位恢复、长稳、加载体验，以及 current active regression 清理。

## 7. 后续节点状态

| 节点 | 目标 | 当前状态 |
|---|---|---|
| M2 | 640×480 真实媒体双板第一闭环 | **FIX6 真板 `[B] PASS`：Master HDMI 出图、NEXT/PREV、自动轮播；节点继续处理恢复/加载体验/回归债务** |
| M3 | source-synchronous 数据面达到 1080p packed-YUV422 等效持续吞吐；720p 仅作排错 | 未开始完整验收 |
| M4 | Master 真实 1920×1080 静态图 + UI/OSD | 未完成 |
| M5 | 视频、切换、转场、音频 | 未完成 |
| M6 | 最终双板 1080p 长稳与故障恢复 | 未完成 |

当前可以表述“640×480 静态图片真实双板链路已真板通过”；仍没有证据允许表述“1080p 持续视频已支持”。

## 8. 当前验证顺序

1. 以 `M2_FIX6_BOARD_PASS_20261005` 作为当前可回退真板基线，后续改动必须能回到该版本。
2. A 线优先量化并缩短 TF/BMP 加载耗时；不要在未测量前盲目修改多个存储模块。
3. C 线把 Loading 从整屏替换改为“保留上一帧 + 小型 overlay”，并保持 publish/fault 语义不变。
4. B 线先清理 `tb_p1_sdram_cached_adapter` active regression，再继续异常/复位/长稳门禁。
5. 14 线链继续作为静态图片基线；持续视频另开高速数据面方案，不把本次图片 PASS 当作视频带宽证据。

当前 full audit 并非全绿：完整 640×480 mailbox、物理 pin fault、主要 M2 链路均通过，但仍有 1 个 ACTIVE/DEEP gate 失败和若干历史/可选测试失败。

## 9. 更新纪律

每次候选状态变化只在本文修改“当前状态”。`docs/develop_records/` 只追加过程记录，不回写成新的权威结论。任何 `[S]` 必须注明对应 Top/candidate/report；任何 `[B]` 必须注明实际板上目标现象。BitGen 成功、代码完成、静态接口检查或旧版本 PASS 均不得替代对应证据等级。
