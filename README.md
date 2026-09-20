# 基于 EG4S20 的 HDMI 多媒体播放系统

这是一个面向校园、园区信息发布和应急广播场景的 FPGA HDMI 多媒体终端。项目目标是在安路 HX4S20C / EG4S20BG256 上完成从 TF/FAT32/BMP 或帧序列数据到 internal SDRAM framebuffer，再到 HDMI 显示输出的完整链路，不依赖外部 CPU 或 MCU。

当前稳定基线是 **P1-05A：internal SDRAM framebuffer → HDMI_B**。它使用固定的 640×480 RGB888 诊断图案验证 SDRAM、CDC、行预取、ping-pong line buffer 和 HDMI 输出链路；TF/FAT32/BMP 播放属于下一阶段 P1-05B，尚未作为已完成能力对外宣称。

## 当前工程入口

| 项目 | 配置 |
|---|---|
| FPGA | HX4S20C / EG4S20BG256 |
| TD 工程 | `FPGA_Competition_HDMI.al` |
| 当前顶层 | `src/top/p1_hx4s20c_sdram_hdmi_top.v` |
| HDMI rollback top | `src/top/p1_hx4s20c_hdmi_board_top.v` |
| 管脚约束 | `constraints/p1_hx4s20c_hdmi_board.adc` |
| 时序约束 | `constraints/p1_hx4s20c_hdmi_board.sdc` |
| 综合/实现工具 | Anlogic TD 6.2.1 |
| 仿真工具 | QuestaSim 10.7c |

P1-05A 保留 P1-04C 已验证的 HDMI_B 管脚、50 MHz → 25/125 MHz PLL、APUG092/PHY、复位和 EDID 边界。当前状态、证据等级和最新时序结果以 [`docs/03_plan_and_status.md`](docs/03_plan_and_status.md) 为准；README 不复制详细 timing、资源和回归表格。

## 快速开始

### 使用 TD

1. 用 TD 6.2.1 打开 `FPGA_Competition_HDMI.al`。
2. 确认顶层为 `p1_hx4s20c_sdram_hdmi_top`，并使用 `constraints/` 下的 ADC/SDC。
3. 依次执行综合、布局布线、STA；需要生成 bitstream 时再执行 BitGen。
4. 任何 RTL、约束或工程设置变更后，都必须重新完成实现和 STA，不能直接继承旧报告的裕量。

TD 自动生成的 run 目录和报告用于本地分析，按 [`CONTRIBUTING.md`](CONTRIBUTING.md) 的规则处理，不要用 `git add .` 将生成物批量提交。

### 使用 QuestaSim

从仓库根目录进入 `sim_work`，再运行相对路径脚本。例如：

```powershell
cd sim_work
vsim -c -do ../sim_tb/framebuf/run_p1_sdram_cached_adapter.do
vsim -c -do ../sim_tb/framebuf/run_p1_sdram_cached_adapter_apug011_official.do
vsim -c -do ../sim_tb/integration/run_p1_sdram_hdmi_cached_chain.do
```

回归脚本应输出 `PASS`。APUG011 受保护模型可能产生供应商源文件自身的 warning；是否通过以测试平台的检查结果为准。更多仿真入口见 [`sim_tb/README.md`](sim_tb/README.md) 及各子目录 README。

## 代码结构

```text
FPGA_Competition_HDMI/
├─ FPGA_Competition_HDMI.al       # 唯一 TD 工程
├─ src/                            # RTL、顶层和厂商 IP 封装
├─ constraints/                    # ADC/SDC 及实验约束
├─ sim_tb/                         # QuestaSim testbench 和回归脚本
├─ ip/                             # 工程 IP 资源
├─ tools/                          # 辅助工具
└─ docs/                           # 权威文档、开发记录和历史资料
```

模块职责、时钟域和数据链路见 [`docs/01_architecture.md`](docs/01_architecture.md)。

## 权威文档

项目说明与开发口径分开维护：

- [`docs/01_architecture.md`](docs/01_architecture.md)：系统架构、模块边界、时钟/CDC 和冻结边界。
- [`docs/02_implementation_goals.md`](docs/02_implementation_goals.md)：阶段目标、验收条件和禁止越级的证据要求。
- [`docs/03_plan_and_status.md`](docs/03_plan_and_status.md)：唯一的进度、验证结果和状态等级权威。
- [`docs/04_use_cases.md`](docs/04_use_cases.md)：产品场景、演示顺序和当前对外表述。

开发过程记录、候选方案和阶段复盘统一放在 [`docs/develop_records/`](docs/develop_records/)；历史文档放在 `docs/olds/`，不作为当前状态依据。

## 参与开发

分支、提交、仿真和文档规则见 [`CONTRIBUTING.md`](CONTRIBUTING.md)，仓库目录边界见 [`STRUCTURE.md`](STRUCTURE.md)。提交前请至少完成受影响模块的 QuestaSim 回归，并在 PR 中记录结果；涉及 active design 的修改还必须附 TD6.2.1 实现和 STA 结果。
