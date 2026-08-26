# 项目目录结构（工程规范）

命名约定：全小写、语义明确、一个目录只干一件事；用 `/` 分隔；避免中英文混排与空格。

```
FPGA_Competition_HDMI/
├─ FPGA_Competition_HDMI.al        # TangDynasty 工程文件（用 TD 打开管理，勿手改）
├─ STRUCTURE.md                    # 本文件（目录规范）
├─ README.md                       # 项目总览（指向 STRUCTURE.md / docs/）
├─ .gitignore                      # 版本忽略规则
├─ docs/                           # 设计文档（01~09：需求/架构/计划/风险/验证/视频/场景/卖点/实现矩阵）
├─ src/                            # ★ 设计代码（可综合 RTL）
│  ├─ README.md                    # 子模块划分与命名约定
│  ├─ top/                         # 顶层模块、时钟、复位
│  ├─ storage/                     # SD读卡 / FAT32 / BMP解析 / 视频帧序列解析
│  ├─ framebuf/                    # SDRAM控制 / 帧缓冲 / 异步FIFO
│  ├─ display/                     # 行场时序 / 色彩空间 / 缩放 / 增强 / 转场 / OSD / TMDS
│  ├─ audio/                       # HDMI音频包 / 测试音 / 音频数据
│  ├─ interact/                    # 按键 / 拨码 / 状态机 / 数码管 / 双色LED / 蜂鸣器
│  └─ app/                         # 应用场景（信息发布与应急广播业务）
├─ sim/                            # ★ 仿真代码（testbench .v + 仿真脚本 .do）
├─ sim_tb/                         # ★ ModelSim 仿真运行输出（work库/波形/日志，gitignore）
├─ constraints/                    # ★ 约束：时钟(.sdc) + 管脚(.cst/.lpf)，须与官方板卡资料核对
├─ tools/                          # 工具脚本（BMP生成 / 视频转帧 / 字库 / SD卡制作）
└─ data/                           # 测试用图片 / 视频帧序列 / 音频（默认不入库）
```

## 目录职责速查

| 目录 | 内容 | 纳入版本控制 | 重要说明 |
|---|---|---|---|
| `src/` | 可综合 RTL（Verilog） | ✅ | 按子系统分子目录；一个模块一个 `.v` |
| `sim/` | testbench `.v` + 仿真脚本 `.do` | ✅ | 仿真源码，需评审与同步 |
| `sim_tb/` | ModelSim 运行产物 | ❌ | 工作库、波形、日志；只放中间产物 |
| `constraints/` | 管脚 + 时钟/时序约束 | ✅ | **必须**与官方板卡资料/原理图逐项核对，勿由 AI 编 |
| `docs/` | 各阶段设计文档 | ✅ | 评审与答辩依据 |
| `tools/` | 生成/转换脚本 | ✅ | 用 bundled Python 运行 |
| `data/` | 图片/视频帧/音频 | ⚠️ 默认不入库 | 可由 tools 重新生成；个别用 `git add -f`；整体走 Git LFS 另配 `.gitattributes` |

> 早期占位目录 `src/rtl`、`src/tb` 已并入 `src/<子系统>` 与 `sim/`，不再使用。
