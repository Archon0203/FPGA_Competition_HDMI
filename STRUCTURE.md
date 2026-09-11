# 项目目录结构（工程规范）

命名约定：全小写、语义明确、一个目录只干一件事；用 `/` 分隔；避免中英文混排与空格。

```text
FPGA_Competition_HDMI/
├─ FPGA_Competition_HDMI.al         # P1-02B 已验证 TD5.6.2 SDRAM closed baseline
├─ FPGA_Competition_HDMI_P1-03B.al  # APUG092/EG-PHY 双时钟注入 candidate
├─ FPGA_Competition_HDMI_P1-04A.al  # 720p 75/375MHz timing experiment；STA FAIL，无 ADC
├─ FPGA_Competition_HDMI_P1-04B.al  # board-safe 640x480：working PLL + HDMI_B real ADC
├─ README.md
├─ STRUCTURE.md
├─ docs/
│  ├─ 01_architecture.md
│  ├─ 02_implementation_goals.md
│  ├─ 03_plan_and_status.md
│  ├─ 04_use_cases.md
│  ├─ develop_records/              # 阶段设计/验证记录
│  ├─ evidence/                     # 已确认的工具/真板证据快照
│  └─ olds/                         # 历史文档，只读留存
├─ src/                             # 可综合 RTL
│  ├─ top/                          # 顶层、复位、PLL、vendor wrappers
│  ├─ vendor/anlogic/               # 官方 protected/reference source，只读
│  ├─ storage/                      # SD/FAT32/BMP/.vseq
│  ├─ framebuf/                     # SDRAM adapter/arbiter/framebuffer/line buffer
│  ├─ display/                      # HDMI adapter、pattern、OSD、缩放、增强等
│  ├─ audio/
│  ├─ interact/
│  └─ app/
├─ ip/                              # TD IP Generator 配置输入（.ipc）
├─ sim_tb/                          # Questa testbench 与 .do
│  ├─ top/
│  ├─ storage/
│  ├─ framebuf/
│  ├─ display/
│  ├─ integration/
│  ├─ audio/
│  ├─ interact/
│  └─ app/
├─ sim_work/                        # Questa 运行目录/中间产物
├─ constraints/                     # SDC + board ADC/templates
├─ tools/                           # 内容制备/测试数据生成工具
└─ data/                            # 测试素材
```

## 当前 P1 工程边界

| 工程 | TOP | 用途 | 板级状态 |
|---|---|---|---|
| `FPGA_Competition_HDMI.al` | `p1_apug011_td_top` | 已收口 APUG011/内部 SDRAM backend，150MHz timing closed | `[S]`，不是完整 HDMI board build |
| `FPGA_Competition_HDMI_P1-03B.al` | `p1_apug092_td_top` | APUG092 + EG PHY 的 injected-clock integration | candidate；无 ADC |
| `FPGA_Competition_HDMI_P1-04A.al` | `p1_hx4s20c_hdmi_smoke_top` | 50MHz -> 75/375MHz -> 720p experimental color bars | SynOpt PASS but STA FAIL；无 ADC，禁止烧板 |
| `FPGA_Competition_HDMI_P1-04B.al` | `p1_hx4s20c_hdmi_board_top` | working official 50->25/125MHz + 640x480 bars + APUG092/EG PHY + HDMI_B real pins | board-safe candidate；待 TD P&R/BitGen/真板 |

P1-04B 已导入用户实测通过的 official `lab_ex4_tf` 50MHz/HDMI/DDC ADC 映射，并刻意不使用 KEY1/KEY2。640x480 与官方样例相同，是首次安全点亮基线；720p 后续单独做 timing closure。

## 目录职责速查

| 目录 | 内容 | 关键规则 |
|---|---|---|
| `src/` | 可综合 RTL | project-owned 逻辑与 vendor 源边界分离；官方 protected/source 不重构 |
| `src/vendor/anlogic/` | 安路官方 reference/protected 源 | 只读；通过 wrapper 对接 |
| `sim_tb/` | TB + `.do` | 自动自检；P1-03 project-owned HDMI TB 已获得 PASS 证据 |
| `sim_work/` | 仿真运行产物 | 不作为源代码 |
| `constraints/` | 时钟和 package pin 约束 | 真板 ADC 必须来自 HX4S20C 官方工程/原理图，不使用占位 pin |
| `ip/` | `.ipc` 再生成输入 | P1-04A 75/375 IPC 保留为实验资料；P1-04B 以 working official video_pll 参数为源 |
| `docs/develop_records/` | 每阶段设计与验证记录 | 记录假设、证据和未验证边界 |
| `docs/evidence/` | 已获得的工具/真板结果 | 只保存确实执行过的证据，不用代码存在替代 PASS |

> Questa 统一从 `sim_work` 调用 `sim_tb/**/run_*.do`。P1-04A 不再作为烧板候选。当前首次可进入完整 SynOpt/PhyOpt/BitGen 验证的是 P1-04B；只有 timing 全闭合后才允许下载。
