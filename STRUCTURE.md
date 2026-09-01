# 项目目录结构（工程规范）

命名约定：全小写、语义明确、一个目录只干一件事；用 `/` 分隔；避免中英文混排与空格。

```
FPGA_Competition_HDMI/
├─ FPGA_Competition_HDMI.al        # TangDynasty 工程文件（用 TD 打开管理，勿手改）
├─ STRUCTURE.md                    # 本文件（目录规范）
├─ README.md                       # 项目总览（指向 STRUCTURE.md / docs/）
├─ .gitignore                      # 版本忽略规则
├─ docs/                           # 当前有效文档（01 架构 / 02 目标 / 03 计划状态 / 04 用例）
│  ├─ olds/                        # 旧版 01~12 文档，仅留存，不再更新
│  └─ develop_records/             # 开发过程记录（接口/测试向量/回归/阶段 note）
├─ src/                            # ★ 设计代码（可综合 RTL）
│  ├─ README.md                    # 子模块划分与命名约定
│  ├─ top/                         # 顶层模块、时钟、复位
│  ├─ storage/                     # SD读卡 / FAT32 / BMP解析 / 视频帧序列解析
│  ├─ framebuf/                    # SDRAM控制 / 帧缓冲 / 异步FIFO
│  ├─ display/                     # 行场时序 / 色彩空间 / 缩放 / 增强 / 转场 / OSD / TMDS（含 vga_timing、image_enhance）
│  ├─ audio/                       # HDMI音频包 / 测试音
│  ├─ interact/                    # 按键 / 拨码 / 状态机 / 数码管 / 双色LED / 蜂鸣器
│  └─ app/                         # 应用场景（信息发布与应急广播业务）
├─ sim_tb/                         # ★ 仿真测试台源码（testbench .v + .do），按模块分目录，与 src/ 对应
│  ├─ top/                         # tb for 顶层/时钟/复位
│  ├─ storage/                     # tb for SD/FAT32/BMP/.vseq
│  ├─ framebuf/                    # tb for SDRAM/帧缓冲/async_fifo
│  ├─ display/                     # tb for vga_timing/image_enhance/...
│  ├─ audio/                       # tb for HDMI音频/测试音
│  ├─ interact/                    # tb for 按键/拨码/状态机/数码管/LED/蜂鸣
│  └─ app/                         # tb for 应用场景
├─ sim_work/                       # ★ ModelSim 运行产物（work库/波形/日志，gitignore）
├─ constraints/                    # ★ 约束：时钟(.sdc) + 管脚(.cst/.lpf)，须与官方板卡资料核对
├─ tools/                          # 工具脚本（BMP生成 / 视频转帧 / 字库 / SD卡制作）
└─ data/                           # 测试用图片 / 视频帧序列 / 音频（默认不入库）
```

## 目录职责速查

| 目录 | 内容 | 纳入版本控制 | 重要说明 |
|---|---|---|---|
| `src/` | 可综合 RTL（Verilog） | ✅ | 按子系统分子目录；一个模块一个 `.v` |
| `sim_tb/` | testbench `.v` + 运行脚本 `.do` | ✅ | 仿真源码，按模块分类、与 `src/` 对应；需评审 |
| `sim_work/` | ModelSim 运行产物 | ❌ | 工作库、波形、日志；只放中间产物 |
| `constraints/` | 管脚 + 时钟/时序约束 | ✅ | **必须**与官方板卡资料/原理图逐项核对，勿由 AI 编 |
| `docs/` | 当前有效架构/目标/计划状态/用例 | ✅ | 只放权威文档，避免混乱 |
| `docs/olds/` | 旧版 01~12 文档 | ✅ | 仅留存，不再更新 |
| `docs/develop_records/` | 开发过程记录 | ✅ | 接口/测试向量/回归/note 统一归档 |
| `tools/` | 生成/转换脚本 | ✅ | 用 bundled Python 运行 |
| `data/` | 图片/视频帧/音频 | ⚠️ 默认不入库 | 可由 tools 重新生成；个别用 `git add -f`；整体走 LFS 另配 `.gitattributes` |

> 仿真运行统一在 `sim_work` 目录执行；testbench 源码与运行脚本放在 `sim_tb/<子系统>/`。
