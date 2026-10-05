# 项目结构

当前仓库固定为 **两个长期 TD6.2.1 工程 + 一套共享 RTL + 两套角色约束**。当前冻结基线为 `M2_FIX6_BOARD_PASS_20261005`，状态以 `docs/03_plan_and_status.md` 为准。

## 1. 构建入口

| 角色 | 工程 | Top | 约束 |
|---|---|---|---|
| Master | `FPGA_Competition_HDMI_MASTER.al` | `m2_master_tf_hdmi_top` | `constraints/master/master.adc` + `master.sdc` |
| Slave | `FPGA_Competition_HDMI_SLAVE.al` | `m2_slave_media_tx_top` | `constraints/slave/slave.adc` + `slave.sdc` |

两份 `.al` 直接引用同一个 `src/`。不要复制 RTL，也不要创建第三个 active TD 工程。

## 2. 目录

```text
FPGA_Competition_HDMI/
├─ FPGA_Competition_HDMI_MASTER.al
├─ FPGA_Competition_HDMI_SLAVE.al
├─ constraints/
│  ├─ master/
│  └─ slave/
├─ src/
│  ├─ top/              # active / rollback top
│  ├─ app/              # 控制与应用状态机
│  ├─ storage/          # SD/TF、FAT32、BMP、媒体服务
│  ├─ dual_board/       # UART、mailbox、remote frame
│  ├─ framebuf/         # SDRAM、CDC、framebuffer、line buffer
│  ├─ display/          # HDMI、Loading、OSD/图像处理
│  ├─ audio/
│  ├─ interact/
│  └─ vendor/anlogic/   # 厂商 IP / wrapper，谨慎修改
├─ sim_tb/              # 单元、子链、集成、full_audit TB
├─ tools/               # 静态审计与 Questa 回归工具
├─ docs/
│  ├─ 01_architecture.md
│  ├─ 02_implementation_goals.md
│  ├─ 03_plan_and_status.md
│  ├─ 04_use_cases.md
│  ├─ 05_line_A_media_plan.md
│  ├─ 06_line_B_framebuffer_plan.md
│  ├─ 07_line_C_presentation_plan.md
│  ├─ 08_three_line_integration_flow.md
│  ├─ develop_records/
│  └─ olds/
├─ README.md
└─ STRUCTURE.md
```

## 3. 当前职责

```text
Slave:
  TF/FAT32/BMP -> media service -> remote-frame TX

Master:
  control -> remote-frame RX -> SDRAM/framebuffer
          -> Loading/display pipeline -> HDMI
```

当前 M2 已在真板完成静态图片双板闭环、手动切换和自动轮播。加载时延、Loading UI 形态以及后续视频高速链路仍是后续任务。

## 4. 共享源码与约束纪律

- `src/` 是唯一可综合源码树；
- Master 只加载 `constraints/master/`，Slave 只加载 `constraints/slave/`；
- `src/vendor/anlogic/**` 不做无意义格式化或编码转换；
- 修改共享模块后，受影响的两块板必须分别重新构建；
- 修改 `.adc` 后必须重新完整 P&R/BitGen，不能复用旧 bitstream。

FIX6 的 14 线 J1 映射由 static audit 固化，具体表见 `constraints/README.md`。

## 5. 验证入口

```powershell
.\run_full_project_audit_questa.bat
```

结果输出到：

```text
sim_work/full_project_audit/
```

当前板级功能已 PASS，但全仓回归仍存在已知仿真债务；不要把“板上能工作”写成“所有 TB 已通过”。

## 6. 文档纪律

`docs/03_plan_and_status.md` 是唯一状态权威。开发过程与板测记录放 `docs/develop_records/`，历史方案放 `docs/olds/`。
