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

M2 **尚未关闭**。当前只完成了其中的“Slave 本地真实媒体子门禁”。

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

这组报告只证明当时对应 netlist 的实现状态，**不能作为 DIAG5、DUALCTRL、DUALCTRL2 或 FIX1 的 `[S]` 证据**。当前 FIX1 仍需重新 synthesis → P&R → final STA → BitGen 后才能记 `[S]`。

资源分析记录显示 `line_buffer_pingpong` 是显著 LUT 消耗项；但资源优化属于后续任务，不能与当前控制正确性证据混写。本轮文档整理不改变任何 RTL。

### 5.3 未通过：真实媒体双板切换/轮播

第一次把 M1 控制接到真实 TF 媒体后，板上出现：

- 自动播放约每几秒使画面闪/抖一次，但通常仍显示原图；
- NEXT/PREV 多数只能造成画面扰动，不能稳定切换；
- 取出 TF、等待、重新插卡后，按键曾能成功切换一次。

因此：

```text
M2 real-media NEXT/PREV                 未通过
M2 real-media PLAY/PAUSE + carousel     未通过
M2 dual-control board gate              未通过
```

后续代码审查提出 `OPEN -> ACCEPTED` 被 Master 过早视为“整图完成”的问题，并形成 `OPEN -> ACCEPTED -> STATUS polling -> DONE` 的 DUALCTRL2 候选；但该候选首次综合又暴露 `source_valid` 未声明的接口错误。

当前 FIX1 已在源码层补齐 `source_valid` 端口并连接到 `media_succeeded`，但**用户尚未提供 FIX1 重新综合、Questa 或真板结果**。因此当前 FIX1 只能记为“待验证候选”，不能写 PASS：

```text
DUALCTRL2 FIX1 compile/synthesis         —
DUALCTRL2 FIX1 Questa                    —
DUALCTRL2 FIX1 final STA                 —
DUALCTRL2 FIX1 board switching           —
```

### 5.4 Slave TD 工程文件问题

协作者从仓库主分支打开 `FPGA_Competition_HDMI_SLAVE.al` 时曾出现 TD6.2.1 “Unable to write the project file / Save As”。对上传仓库快照的比较发现，记录的 `origin/main` Slave 工程文件含 5 个重复 `<File Path=...>` 条目，而用户本机可打开版本无重复。

这属于工程文件维护问题，不属于 M2 媒体功能 PASS。当前候选包使用去重 `.al`，并提供 `tools/check_td_project.py` 做重复路径/CRLF 检查；是否已合并回团队主分支仍由团队 Git 流程确认。

## 6. M2 关闭门槛

M2 只有同时满足以下条件才可关闭：

1. `[C]`：真实 TF/FAT32/BMP 经完整双板媒体链到 Master 显示可复现；
2. `[S]`：Master/Slave 对应最终 M2 candidate 均完成 TD6.2.1 final STA，setup/hold 0 violation；
3. `[B]`：显示器接 Master HDMI，至少 4 张真实 BMP 可稳定 NEXT/PREV 与自动轮播；
4. `[B]`：断链、错包、坏文件或重置时不提交半帧，能保持上一帧或 fallback；
5. 控制命令必须以真实媒体事务完成为边界，不能把 UART ACK/`ACCEPTED` 当成整帧完成。

当前状态：**以上 M2 汇合门槛均未全部满足。**

## 7. 后续节点状态

| 节点 | 目标 | 当前状态 |
|---|---|---|
| M2 | 640×480 真实媒体双板第一闭环 | **进行中；local TF/BMP 子门禁 `[B] PASS`，双板切换未通过** |
| M3 | source-synchronous 数据面达到 1080p packed-YUV422 等效持续吞吐；720p 仅作排错 | 未开始完整验收 |
| M4 | Master 真实 1920×1080 静态图 + UI/OSD | 未完成 |
| M5 | 视频、切换、转场、音频 | 未完成 |
| M6 | 最终双板 1080p 长稳与故障恢复 | 未完成 |

当前没有任何证据允许对外表述“1080p 已支持”或“真实双板媒体链已通过”。

## 8. 当前验证顺序

在继续 M2 前按以下顺序收口，不并行引入新的资源优化：

1. FIX1 重新跑 Slave/Master 源码分析与综合；
2. 跑 real-media UART bridge / coordinator / dispatcher / media-write CDC 相关 Questa 回归；
3. 两角色重新 P&R + final STA + BitGen；
4. Slave-alone：确认单图加载后长期稳定，不周期性重载；
5. Dual-control：暂停自动轮播，单步验证 `0 -> 1 -> 2 -> ...` 与 PREV；
6. 再恢复自动轮播，确认“图片完成后计时”而不是“ACK 后计时”；
7. 只有低速真实媒体控制稳定后，才继续 M2-B0 高速 source-synchronous PRBS/CRC/sequence 门禁。

## 9. 更新纪律

每次候选状态变化只在本文修改“当前状态”。`docs/develop_records/` 只追加过程记录，不回写成新的权威结论。任何 `[S]` 必须注明对应 Top/candidate/report；任何 `[B]` 必须注明实际板上目标现象。BitGen 成功、代码完成、静态接口检查或旧版本 PASS 均不得替代对应证据等级。
