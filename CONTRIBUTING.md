# 参与开发（Contribution Guide）

> 团队协作详见 [`docs/olds/10_team_workflow.md`](docs/olds/10_team_workflow.md)。核心规则如下。

## 角色（GitHub 账号）
- 张宗（Owner，`Archon0203`）：审核并合并 PR，维护 main 与文档。
- 曾雨婷（队长，`ZYT-zyt111`）：统筹、开发、经授权可代审。
- 杨文轩（队员B，`ywx324`）：开发、开 PR；可走上游分支，也可 fork 隔离。

## 开发线分工与集成边界

当前采用“三线并行 + 集成负责人”模式，目标路线为双板主从架构和 1080p 输出。三条开发线在接口契约冻结后并行实现，集成节点统一合并和验证。

| 负责人 | 开发线 | 主要职责 | 部署板卡与边界 |
|---|---|---|---|
| 张宗 | C 线 + 集成 | 主板 UI、交互、`media_cmd`、OSD、缩放、转场、音频和 1080p UI 适配；维护公共接口、集成分支、顶层与约束；组织综合、布局布线、STA、BitGen 和真板验收 | C 线主要运行在主板；集成负责人统一维护 `src/top/**`、`constraints/**` 和 TD 工程，不承接 A/B 线内部模块实现 |
| 曾雨婷 | A 线 | 从板 TF/FAT32/BMP 解析、媒体目录、预取、SDRAM、descriptor/packet，以及 1080p 媒体数据供给 | 主要运行在从板；只修改 A 线所有权范围，按冻结的 descriptor、packet 和板间接口提交模块 |
| 杨文轩 | B 线 | 从板发送、主板接收、SPI/GPIO/PRBS/CRC/CDC、line/tile buffer，以及 HDMI 1080p 时序和安全提交 | 跨从板发送端与主板接收端；只修改 B 线所有权范围，按冻结的板间链路和显示时序接口提交模块 |

### 集成与阶段规则

1. `M0` 是已完成的 P0/P1-05A 基线；`M1` deterministic 双板控制门禁已关闭；**当前节点为 `M2`**。P1-05B 作为 `M2` 的双板架构第一闭环。Slave 本地 TF/BMP 诊断 PASS 不等于 M2 双板完成。
2. `M1` 的双板可视化控制闭环已经在真板通过；当前进入 `M2`。`M3` 直接以 1080p packed-YUV422 等效吞吐和 1080p PHY 可行性为硬门禁，1280×720 只允许作为故障隔离 profile，不能作为节点完成条件。
3. 公共接口（`media_cmd`、descriptor/packet、板间链路、时钟/复位、显示提交等）由集成负责人先定义并冻结；接口变更必须先在 PR 中说明影响范围，再由集成负责人协调 A/B/C 三线同步修改。
4. C 线可先用 deterministic raster、固定 catalog 和 PRBS mock 开发按键/旋钮/转轮/UI；真实选图范围、媒体类型、播放完成/错误必须接入 A 线 `catalog/descriptor/status`，真实缩放/OSD/转场验收必须接入 B 线 `canonical raster/frame_boundary/underflow`。mock 通过不等于双板集成通过。
5. 旋钮采用外接增量式正交编码器 A/B + 按压开关的候选方案，优先使用 40-pin GPIO；pin ownership、电平、消抖、CDC 和约束由集成负责人冻结后才能上板。
6. 双板构建产物必须分开保存：`master.bit` 对应主板 `master_top + master ADC/SDC`，`slave.bit` 对应从板 `slave_top + slave ADC/SDC`。更换 Top 或约束后必须完整执行 synthesis、P&R、STA、BitGen，并在烧录记录中写明板号、角色、commit 和 bitstream 哈希。
7. A 线和 B 线不得直接修改对方所有权范围，也不得绕过已冻结接口建立隐式依赖。跨线需求通过接口、stub 或测试数据提出。
8. 每个 `M` 节点由集成负责人建立集成分支并合并 PR，完成相应的综合、布局布线、STA、BitGen 和真板验证后，更新 `docs/03_plan_and_status.md` 与 `docs/08_three_line_integration_flow.md` 的状态。
9. 集成发现问题时，优先回退到最近一个通过真板验证的基线；问题归属到对应开发线修复，集成负责人负责复测和重新合并。

## TD 工程与共享 RTL 纪律

仓库只允许两个 active TD6.2.1 工程：

```text
FPGA_Competition_HDMI_MASTER.al
FPGA_Competition_HDMI_SLAVE.al
```

两者必须直接引用同一套 `src/`；禁止为了 TD 工程方便复制一份 `rtl/` 到角色目录。Master 约束只能来自 `constraints/master/`，Slave 约束只能来自 `constraints/slave/`。新增第三个 `.al`、复制共享 RTL、或让一个工程同时加载两套角色约束，均视为需要在 PR 中先纠正的工程结构问题。

M2~M6 顶层演进也沿用这两个 `.al`：可以修改其 `TOP_MODULE` 和 Source_Files，但不再创建阶段性 active 工程。历史验证工程只保留在 Git 历史/开发记录中。

## 提交流程（一句话）
克隆原仓库 -> 建 feature 分支 -> 改 -> ModelSim 自检 PASS -> commit -> push -> PR 到 main -> 等 Approve -> Squash and merge

## 规则
1. main 被保护：禁止直接 push 到 main，必须走 PR。
2. 分支命名：feat/ fix/ docs/ refactor/。
3. 提交信息：type(scope): subject，如 feat(framebuf): add async_fifo。
4. 每个 src/ 模块必须有对应 sim_tb/tb_*.v，仿真输出 PASS；贴结果到 PR。
5. 不提交生成物：*.bit、*.db、*.area、sim_work/ 产物、data/ 均不入库。
6. 网络：连不上 GitHub 先配代理 git config http.proxy http://127.0.0.1:7890。
7. 文档组织：`docs/` 根目录只保留 `01~08` 规范文档；其中 `docs/03_plan_and_status.md` 是**唯一进度/证据状态权威**。开发过程、验证步骤、阶段说明统一放 `docs/develop_records/`，原始日志/截图/报告统一放 `docs/develop_records/evidence/`；历史方案放 `docs/olds/` 或 `docs/develop_records/`，不得覆盖 `03` 的当前状态。

## 快速开始
```powershell
git config http.proxy  http://127.0.0.1:7890
git config https.proxy http://127.0.0.1:7890
git config user.name "你的姓名"; git config user.email "你的邮箱@users.noreply.github.com"
git clone https://github.com/Archon0203/FPGA_Competition_HDMI.git
cd FPGA_Competition_HDMI
```
## Modelsim相关
具体操作在群文件分享的教程里，注意不要直接使用TangDynasty在项目文件夹/simulation/下生成的.do脚本。如果未创建新仿真工程而直接使用该脚本，则会直接覆盖上一个仿真工程产生的文件


## Git 安全与发布包规则

1. **任何发布 ZIP 都不得携带 `.git/` 目录。** `.git/` 含 branch/index/remotes/history，本地覆盖可能破坏团队仓库状态。
2. 必须保留 `.gitignore`；本仓库新增 `.gitattributes`，固定 TD `.al/.adc/.sdc/.cfg/.prj` 为 CRLF，RTL/Markdown/Tcl 为 LF，避免跨平台产生整文件行尾 diff。
3. TD 的 `*_Runs/`、Questa `work/`、`modelsim.ini`、`.bit/.db/.qdb/.wlf`、日志、minidump 和 `data/` 默认不提交。
4. 集成发布包应先在一个**没有 `.git/` 的临时目录**检查，再复制到现有 clone；不要反向把临时目录的隐藏文件覆盖回仓库。
5. 提交前使用 `git status --short`、`git diff --stat`、`git add -p`。若看到上百个仅行尾变化的文件，应先停止并检查 `.gitattributes`/编辑器 EOL 设置。
6. 厂商加密 IP（例如 `*.enc.v`）不得被格式化、重新编码或自动换行；`.gitattributes` 已将其标为 `-text`。
