# FPGA 双板 HDMI 多媒体播放系统

基于两块安路 HX4S20C / EG4S20BG256 的 FPGA 多媒体播放项目。当前架构由 **Slave 负责 TF/FAT32/BMP 媒体读取与发送，Master 负责控制、帧缓存和 HDMI 输出**。

## 当前冻结版本

**基线：`M2_FIX6_BOARD_PASS_20261005`**

已在真板确认：

- TF 卡 640×480 / 24-bit BMP 可由 Slave 读取；
- 图片通过 14 线双板数据链传到 Master；
- Master HDMI 可正常显示真实图片；
- NEXT / PREV 可切图；
- 自动轮播可工作；
- FIX6 修正的 J1 / FPGA 球位映射已在板上验证有效。

当前仍有三项未收口：

1. 图片加载时间较长，切换体验明显慢于官方样例；
2. 加载期间当前 UI 会整屏覆盖图片，后续应改为保留上一帧并叠加小型“加载中”提示；
3. 当前 14 线握手链适合静态图片验证，不作为后续持续视频传输方案。

完整回归并非全绿：完整 640×480 mailbox 与物理 pin fault 仿真已 PASS，但 `framebuf/tb_p1_sdram_cached_adapter` 仍是当前 active regression 的已知失败项；若干历史/可选 TB 也仍需整理。真板功能 PASS 不等价于这些仿真债务已经关闭。

详细冻结记录见：[`docs/develop_records/M2_FIX6_BOARD_PASS_FREEZE_20261005.md`](docs/develop_records/M2_FIX6_BOARD_PASS_FREEZE_20261005.md)。项目进度与证据等级以 [`docs/03_plan_and_status.md`](docs/03_plan_and_status.md) 为唯一权威。

## 当前工程入口

| 角色 | TD 工程 | Top | 主要职责 |
|---|---|---|---|
| Master | `FPGA_Competition_HDMI_MASTER.al` | `m2_master_tf_hdmi_top` | 控制、双板接收、SDRAM/framebuffer、Loading UI、HDMI |
| Slave | `FPGA_Competition_HDMI_SLAVE.al` | `m2_slave_media_tx_top` | TF/FAT32/BMP、媒体调度、双板发送 |

工具链：**Anlogic TD 6.2.1**；仿真：**QuestaSim 10.7c**。

## 项目结构

```text
FPGA_Competition_HDMI/
├─ FPGA_Competition_HDMI_MASTER.al
├─ FPGA_Competition_HDMI_SLAVE.al
├─ constraints/          # Master / Slave 引脚与时序约束
├─ src/                  # 唯一 RTL 源码树
│  ├─ top/
│  ├─ app/
│  ├─ storage/           # TF / FAT32 / BMP
│  ├─ dual_board/        # 双板控制与媒体链
│  ├─ framebuf/          # SDRAM / framebuffer / line buffer
│  ├─ display/           # HDMI / Loading / OSD 等
│  ├─ audio/
│  ├─ interact/
│  └─ vendor/anlogic/
├─ sim_tb/               # QuestaSim testbench
├─ tools/                # 静态检查与回归脚本
├─ docs/                 # 架构、计划、三线任务、开发记录
├─ README.md
└─ STRUCTURE.md
```

更详细的目录说明见 [`STRUCTURE.md`](STRUCTURE.md)。

## 验证入口

上板前建议至少执行：

```powershell
.\run_full_project_audit_questa.bat
```

重点关注：

- J1 电气映射 static audit；
- `tb_m2_physical_pin_fault_signature`；
- `tb_m2_full_frame_mailbox_640x480`；
- 当前 active regression 的失败项。

修改 `.adc`、Top、共享 RTL 或 vendor wrapper 后，Master / Slave 都必须重新 **Synthesis → P&R → STA → BitGen**，不要复用旧 `_Runs` 中的 bitstream。

## 当前双板职责

```text
Slave
TF -> FAT32 -> BMP -> media service
                 |
                 v
        14-line image transport
                 |
                 v
Master
RX -> SDRAM/framebuffer -> display pipeline -> HDMI
        ^
        |
  key / carousel control
```

当前 14 线连接和 FIX6 正确球位见 [`constraints/README.md`](constraints/README.md) 与冻结记录。后续视频链路将另行设计，不在本基线中扩展。

## 文档约定

- `docs/03_plan_and_status.md`：唯一当前状态权威；
- `docs/01~08`：架构、目标、三线计划与集成路线；
- `docs/develop_records/`：阶段开发与板测记录；
- `docs/olds/`：历史方案。

本次冻结只更新文档与状态记录，不修改 `.git/` 内容。
