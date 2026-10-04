# 基于 EG4S20 的双板 1080P HDMI 多媒体播放系统

这是一个面向校园、园区信息发布和应急广播场景的 FPGA 多媒体终端。项目使用两块安路 HX4S20C / EG4S20BG256，目标是在不依赖外部 CPU/MCU 的前提下完成 TF/FAT32/BMP/视频帧序列读取、双板媒体传输、1920×1080 HDMI 视频/音频、OSD/字幕、缩放、转场、实时参数调节和音频可视化。

## 当前状态（以 `docs/03_plan_and_status.md` 为唯一权威）

当前节点为 **M2**。已确认的关键边界：

- M1 115200 framed UART + deterministic 双板可视控制门禁已通过；
- M2 已取得 **真实 TF/FAT32/BMP 640×480 -> Slave SDRAM -> Slave HDMI 的本地真板 PASS**；
- 真实媒体双板 NEXT/PREV、PLAY/PAUSE、自动轮播 **尚未通过**。已观察到周期闪动但图片不变、按键多数不能完成切换；
- DUALCTRL2 为修复“把 `ACCEPTED` 误当整图完成”的候选；FIX1 已补齐 `source_valid` 接口，但尚未取得用户侧重新综合/Questa/真板证据；
- source-synchronous 高速媒体数据面、Master-owned 最终媒体显示和 1920×1080 均未完成。

详细状态、证据等级和下一门禁只维护在 [`docs/03_plan_and_status.md`](docs/03_plan_and_status.md)。开发过程和历史推断不覆盖该文件。

最终职责仍保持：

```text
Slave：TF/FAT32/BMP/vseq、媒体目录、预取、源缓存、line/tile packet 生产
                      ↓ 高速数据面
Master：控制/状态、接收/CDC、line/tile buffer、缩放、OSD、转场、音频、1080P HDMI
```

当前 Slave HDMI 仅作为 M2 本地真实媒体诊断出口，不代表最终显示职责发生变化。

## 当前工程入口

仓库从现在起只保留 **两个长期 TD6.2.1 主工程**，两者共享根目录 `src/` 的同一套 RTL，只使用各自角色约束：

| 板卡角色 | TD 工程 | 当前 Top | 角色约束 |
|---|---|---|---|
| Master 主板 | `FPGA_Competition_HDMI_MASTER.al` | `m1abc_master_control_top` | `constraints/master/master.adc` + `master.sdc` |
| Slave 从板 | `FPGA_Competition_HDMI_SLAVE.al` | `m2_slave_tf_hdmi_top` | `constraints/slave/slave.adc` + `slave.sdc` |

构建主板 bitstream 时只打开 `FPGA_Competition_HDMI_MASTER.al`；构建从板 bitstream 时只打开 `FPGA_Competition_HDMI_SLAVE.al`。**不得复制另一角色的 bitstream，也不得新建第三个 active `.al`。** 后续 M2~M6 只演进这两个工程的 Source_Files/Top/约束；RTL 始终以 `src/` 为唯一源码副本。

P1-05A 640×480 SDRAM→HDMI 仍作为已验证的源码/证据 rollback 基线保留在 `src/` 与 `docs/develop_records/`，但不再保留第三个 rollback `.al`，避免构建入口歧义。

其他入口：

| 用途 | 入口 |
|---|---|
| M1ABC Questa 回归 | `sim_tb/m1abc/run_all.bat` |
| M1ABC 验证/关闭记录 | `docs/develop_records/M1ABC_V5_VALIDATION.md` |
| 双工程重构记录 | `docs/develop_records/M1_TWO_PROJECT_REORGANIZATION_20261001.md` |
| M2 入口计划 | `docs/develop_records/M2_REAL_MEDIA_ENTRY.md` |

工具链：Anlogic TD 6.2.1；仿真：QuestaSim 10.7c。

## M1 真板接线

两板断电后连接：

```text
Master J1-8  / FPGA J13 / TX -> Slave  J1-4  / FPGA F13 / RX
Slave  J1-8  / FPGA J13 / TX -> Master J1-4  / FPGA F13 / RX
Master J1-12 / GND            <-> Slave J1-12 / GND
```

不要把两块板的 5 V 互连。当前已由真板确认：FPGA `J13` 对应 J1-8，FPGA `F13` 对应 J1-4。

## M1ABC 上板现象

Slave HDMI_B 接显示器后，双板正常时：

- 约每 2 s 在 4 个 deterministic 页面间轮播；
- Master KEY2=NEXT、KEY3=PREV、KEY4=PLAY/PAUSE；
- Slave 画面左上绿色块表示 link established；顶部红条表示 fault；
- Master/Slave `LED2` 应亮、`LED4` 应灭；activity LED 使用 toggle，肉眼可能表现为闪烁或较暗常亮。

详细步骤见 `docs/develop_records/M1ABC_V5_VALIDATION.md`。

## 1080P 双板设计原则

EG4S20 的逻辑和片内 SDRAM 都有限。1920×1080 一帧有 2,073,600 像素；按历史 32-bit/像素表示，单帧已经接近 2M×32 SDRAM 的全部容量，因此最终架构不采用“Master 内部两张完整 1080P RGB888 framebuffer”的简单复制方案。

主线采用：

```text
Slave 大块媒体缓存/预取
  -> packed YUV422 line/tile
  -> source-synchronous GPIO 数据面
  -> Master FIFO/line/tile buffer
  -> scaler/effects/OSD/audio-visual
  -> 1920×1080 APUG092/HDMI
```

控制面保留低带宽命令/状态通道；媒体数据面单独做高吞吐链路。UART 只用于 M1 bring-up 和控制面验证，不承担 1080P 像素传输。

## 文档权威顺序

> 文档规范：`docs/` 根目录只保留 `01~08` 规范文档。开发过程、验证步骤、日志、截图和阶段性说明一律放入 `docs/develop_records/`，原始证据放 `docs/develop_records/evidence/`。


- `docs/01_architecture.md`：系统架构与最终职责边界；
- `docs/02_implementation_goals.md`：目标与证据门槛；
- `docs/03_plan_and_status.md`：**唯一进度/证据状态权威**；
- `docs/04_use_cases.md`：场景与演示口径；
- `docs/05~07`：A/B/C 三线计划；
- `docs/08_three_line_integration_flow.md`：M0~M6 统一路线；
- `docs/develop_records/M1ABC_V5_VALIDATION.md`：M1ABC 真板验证与关闭记录；
- `docs/develop_records/M2_REAL_MEDIA_ENTRY.md`：M2 真实媒体第一闭环入口。

历史方案放在 `docs/olds/` 和 `docs/develop_records/`，不覆盖当前权威状态。

## Git / GitHub 注意

本发布包是 **repository working-tree snapshot**：保留 `.gitignore` 和 `.gitattributes`，但**故意不包含 `.git/`**，也不包含 TD/Questa 生成目录、bitstream、work library、minidump 等本地生成物。这样可以安全复制到现有 clone 中而不会覆盖分支、remote、index 或本地 Git 历史。

推荐做法：

```powershell
git switch -c feat/m2-real-media-entry
# 将本包内容覆盖/合并到现有 clone 的工作树，绝不要覆盖 .git/
git status
git diff --stat
git add -p
git commit -m "feat(m1): close dual-board ABC bring-up and enter M2"
```

不要对工程目录直接执行 `git add .`；先检查 `git status`，确认没有 TD run、Questa work、`.bit`、日志或大媒体文件。详细规则见 `CONTRIBUTING.md`。


## 2026-10-03 M2 TF DIAG3

Current board-debug candidate restores the proven P1-05A SDRAM SDC exceptions, removes the DIAG2 wide debug counter, and exposes the raw media failure family by HDMI color plus the low nibble on LEDs. See `docs/develop_records/M2_TF_DIAG3_20261003.md`.


## 2026-10-03 M2 TF local PASS / dual-control candidate

真实 TF/FAT32/BMP 640×480 本地 HDMI 已取得真板 PASS。当前双板候选新增 `m2_open_dispatcher`，修复成功加载后无限重复 `OPEN(0)` 导致 Master 换图被覆盖的问题。Master 继续使用 KEY2=NEXT、KEY3=PREV、KEY4=PLAY/PAUSE 和约 2 s 自动轮播。详见 `docs/develop_records/M2_TF_LOCAL_PASS_AND_DUAL_CONTROL_20261003.md`。

### 2026-10-04 M2 dual-control candidate

真实 TF 首图路径保持真板 PASS。双板控制现改为“OPEN 只确认排队，Master STATUS 轮询直到 requested image 真正 DONE 后才允许下一条命令”，避免 2 s 轮播和按键在 TF 加载中覆盖请求。另已修复/规避 Git main 中 Slave `.al` 的 5 个重复 source-file entries，并提供 `tools/check_td_project.py` 检查 TD 工程文件。见 `docs/develop_records/M2_DUAL_CONTROL_COMPLETION_GATE_AND_TD_PROJECT_FIX_20261004.md`。
