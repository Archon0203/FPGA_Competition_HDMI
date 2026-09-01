# 参与开发（Contribution Guide）

> 团队协作详见 [`docs/olds/10_team_workflow.md`](docs/olds/10_team_workflow.md)。核心规则如下。

## 角色（GitHub 账号）
- 张宗（Owner，`Archon0203`）：审核并合并 PR，维护 main 与文档。
- 曾雨婷（队长，`ZYT-zyt111`）：统筹、开发、经授权可代审。
- 杨文轩（队员B，`ywx324`）：开发、开 PR；可走上游分支，也可 fork 隔离。

## 提交流程（一句话）
克隆原仓库 -> 建 feature 分支 -> 改 -> ModelSim 自检 PASS -> commit -> push -> PR 到 main -> 等 Approve -> Squash and merge

## 规则
1. main 被保护：禁止直接 push 到 main，必须走 PR。
2. 分支命名：feat/ fix/ docs/ refactor/。
3. 提交信息：type(scope): subject，如 feat(framebuf): add async_fifo。
4. 每个 src/ 模块必须有对应 sim_tb/tb_*.v，仿真输出 PASS；贴结果到 PR。
5. 不提交生成物：*.bit、*.db、*.area、sim_work/ 产物、data/ 均不入库。
6. 网络：连不上 GitHub 先配代理 git config http.proxy http://127.0.0.1:7890。
7. 文档组织：当前有效设计文档只维护 `docs/01_architecture.md` ~ `docs/04_use_cases.md`；旧版 `01~12` 文档只留在 `docs/olds/`，不再更新；开发过程记录统一放 `docs/develop_records/`，不要混入 `docs/` 根目录。

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
