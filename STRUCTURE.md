# 项目目录结构

当前仓库固定为 **两个长期 TD6.2.1 工程 + 一套共享 RTL + 两套角色约束**。M1ABC 双板可视化控制闭环已真板 PASS，当前进入 M2。最终职责仍是 Slave 负责媒体生产，Master 负责最终 1080P 合成与 HDMI。

## 1. 唯一 TD 构建入口

```text
FPGA_Competition_HDMI_MASTER.al   # Master 主板
FPGA_Competition_HDMI_SLAVE.al    # Slave 从板
```

| 工程 | 当前 Top | 约束 | 当前作用 |
|---|---|---|---|
| `FPGA_Competition_HDMI_MASTER.al` | `m1abc_master_control_top` | `constraints/master/*` | 按键、控制、双向 UART 控制面 |
| `FPGA_Competition_HDMI_SLAVE.al` | `m2_slave_tf_hdmi_top` | `constraints/slave/*` | 真实 TF/FAT32/BMP、本地 SDRAM/HDMI、UART 控制接管 |

两个 `.al` 都直接引用仓库根 `src/`。**工程目录中不再保存 RTL 副本。** 后续 M2~M6 若 Top 演进，只修改这两个工程；不得再增加第三个 active `.al`。

当前 TD Project Path 固定为 `D:/AnlogicProject/FPGA_Competition_HDMI`，与已验证的 TD6.2.1 使用方式一致。

## 2. 目录树

```text
FPGA_Competition_HDMI/
├─ FPGA_Competition_HDMI_MASTER.al
├─ FPGA_Competition_HDMI_SLAVE.al
├─ README.md
├─ STRUCTURE.md
├─ CONTRIBUTING.md
├─ constraints/
│  ├─ README.md
│  ├─ master/
│  │  ├─ master.adc
│  │  └─ master.sdc
│  └─ slave/
│     ├─ slave.adc
│     └─ slave.sdc
├─ src/                         # 唯一 RTL/source tree
│  ├─ top/
│  ├─ app/
│  ├─ storage/
│  ├─ dual_board/
│  ├─ framebuf/
│  ├─ display/
│  ├─ audio/
│  ├─ interact/
│  └─ vendor/anlogic/           # vendor/protected source，只读
├─ sim_tb/
│  ├─ m1abc/                    # 当前双板 aggregate regression
│  ├─ storage/
│  ├─ framebuf/
│  ├─ display/
│  ├─ audio/
│  └─ app/
├─ docs/
│  ├─ 01_architecture.md
│  ├─ 02_implementation_goals.md
│  ├─ 03_plan_and_status.md
│  ├─ 04_use_cases.md
│  ├─ 05_line_A_media_plan.md
│  ├─ 06_line_B_framebuffer_plan.md
│  ├─ 07_line_C_presentation_plan.md
│  ├─ 08_three_line_integration_flow.md
│  ├─ develop_records/          # 所有开发/验证记录
│  │  └─ evidence/              # 日志、截图等原始证据
│  └─ olds/                     # 历史文档，只读
├─ ip/
└─ tools/
```

## 3. 当前 M2 控制集成构建

Master：

```text
FPGA_Competition_HDMI_MASTER.al
  -> shared src/**
  -> constraints/master/master.adc + master.sdc
  -> m1abc_master_control_top
  -> master bitstream
```

Slave：

```text
FPGA_Competition_HDMI_SLAVE.al
  -> shared src/**
  -> constraints/slave/slave.adc + slave.sdc
  -> m2_slave_tf_hdmi_top
  -> slave bitstream
```

M1 真板接线继续使用已验证映射：

```text
Master J1-8  / FPGA J13 / TX -> Slave  J1-4 / FPGA F13 / RX
Slave  J1-8  / FPGA J13 / TX -> Master J1-4 / FPGA F13 / RX
Master J1-12 / GND            <-> Slave J1-12 / GND
```

当前 M2-A/C bring-up 仍由 Slave HDMI_B 输出真实 TF 图片，Master 通过三线 UART 控制选图；后续 M2-B 再把真实媒体数据面与最终显示职责迁回 Master。P1-05A rollback 的 RTL、时序记录与真板证据保留，但不再作为第三个 TD 工程。

## 4. 共享 RTL 纪律

- `src/` 是唯一可综合 RTL/source tree；不得在 `projects/`、`td_*` 或角色目录复制源码。
- Master/Slave 可以引用 `src/` 中不同子集，但公共模块只能存在一份。
- 当前 `src/dual_board/db_uart_tx.v` 已同步为 M1 真板通过工程使用的版本。
- `src/vendor/anlogic/**` 为厂商/加密源，不格式化、不改编码。
- 每次修改共享模块，都必须分别重新构建受影响的 Master/Slave 工程。

## 5. 约束纪律

- Master 只使用 `constraints/master/`。
- Slave 只使用 `constraints/slave/`。
- 板间 pin map、Top port 或时钟变更时，必须更新对应角色约束并重新 synthesis → P&R → STA → BitGen。
- 禁止在一个工程里同时加载 Master 与 Slave 约束。

## 6. 文档和 Git 纪律

`docs/` 根目录只保留 `01~08` 规范文档。开发过程、验证记录、阶段说明统一进入 `docs/develop_records/`，日志/截图等证据进入 `docs/develop_records/evidence/`。

发布 ZIP 不携带 `.git/`、`*_Runs/`、Questa `work/`、bitstream、minidump、TD 日志等本地生成物；`.gitignore` 与 `.gitattributes` 必须保留。
