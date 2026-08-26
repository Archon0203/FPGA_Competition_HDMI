# 10 · 团队协作开发流程（GitHub + main 分支保护）

> 仓库：`Archon0203/FPGA_Competition_HDMI`（公开）
> 规则：对 `main` 的直接 push 被拒绝（"Changes must be made through a pull request"），一切改动必须走 PR，并经审核 + 1 个 Approve 后合并。
> 团队成员（GitHub 账号）：**张宗** = Archon0203（队员A/所有者）、**曾雨婷** = ZYT-zyt111（队长）、**杨文轩** = ywx324（队员B）。

## 0. 角色与权限（当前实际配置）

| 角色 | 姓名 | GitHub 账号 | 权限 | 是否在 Rule1 bypass | 职责 |
|---|---|---|---|---|---|
| **队员A**（所有者） | 张宗 | Archon0203 | **Owner** | ✅ 是（可直推 main） | 建仓、设分支保护、审核并合并 PR、维护 main 与文档 |
| **队长** | 曾雨婷 | ZYT-zyt111 | **Collaborator（Write）** | ❌ 否（必须走 PR） | 统筹、开发、开 PR；经张宗授权可代审 |
| **队员B** | 杨文轩 | ywx324 | **Collaborator（Write）** | ❌ 否（必须走 PR） | 开发、开 PR；可 fork 隔离（可选） |

> 说明：
> - 张宗 是 **Rule1 的 bypass 成员**，可绕过 PR 直接 push 到 main（方便管理员处理/紧急修复）；但团队改动仍建议走 PR。
> - 曾雨婷、杨文轩 是 **Write 成员，不在 bypass 名单**，**不能直接 push main**，必须走 feature 分支 + PR。
> - 三人对 `main` 的修改都要先 `git pull` 同步最新，避免冲突。

## 1. 通用前提（每一位成员，首次必做）

因网络需代理，先给本仓库配 Git 代理（仅影响本项目，可随时取消）：
```powershell
git config http.proxy  http://127.0.0.1:7890
git config https.proxy http://127.0.0.1:7890
```
再确认提交身份：
```powershell
git config user.name  "张宗"       # 或 "曾雨婷" / "杨文轩"
git config user.email "你的账号@users.noreply.github.com"
```
用 `git config --list` 查看是否生效。

> 仿真用 ModelSim，通用命令（在 `sim_tb` 目录）：
> ```powershell
> cd sim_tb
> vsim -c -do ../sim/run_vga_timing.do
> ```

## 2. 张宗（队员A / 仓库所有者 / 审核者）

### 2.1 一次性初始化（已完成）
1. 建公开仓库 `FPGA_Competition_HDMI` 并 push 到 `main`。
2. 设 main 分支保护：Settings → Rulesets → Rule1，Target `main`，勾 Require a pull request before merging（approvals=1）、Block force pushes、Require conversation resolution。
3. Bypass list 添加 **Archon0203**（自己），允许直推 main。
4. Collaborators 添加 **ZYT-zyt111（曾雨婷）** 与 **ywx324（杨文轩）**，角色 **Write**。

### 2.2 日常审核与合并
1. 打开仓库 `pulls`，看待审 PR。
2. 进入某条 PR：Files changed 看 diff -> 留评论 -> 点 Review：没问题 Approve；有问题 Request changes。
3. 通过后点 **Merge pull request（Squash and merge）**，再确认删除源分支。
4. 同步本地：
   ```powershell
   git checkout main; git pull origin main
   ```

### 2.3 张宗自己开发
推荐走 PR（保持 main 干净）；紧急修复可利用 bypass 直推：
```powershell
git checkout -b feature/xxx
git add -A; git commit -m "feat(module): desc"
git push origin feature/xxx        # 走 PR 时用这个
# 紧急时（bypass 允许）可：git push origin main
```

## 3. 曾雨婷（队长 / 仓库协作者 / 统筹）

1. 已接受邀请成为 **Write 成员**。
2. 克隆原仓库：
   ```powershell
   git clone https://github.com/Archon0203/FPGA_Competition_HDMI.git
   cd FPGA_Competition_HDMI
   git config http.proxy  http://127.0.0.1:7890
   git config https.proxy http://127.0.0.1:7890
   git config user.name "曾雨婷"; git config user.email "ZYT-zyt111@users.noreply.github.com"
   ```
3. 建分支并开发：
   ```powershell
   git checkout -b feature/xxx
   # 修改 src/ 与 sim/；在 sim_tb 里跑 ModelSim 自检 PASS
   git add -A; git commit -m "feat(framebuf): add async_fifo"
   ```
4. 推送原仓库并提 PR：
   ```powershell
   git push origin feature/xxx
   ```
   GitHub -> Compare -> base `main` <- compare `feature/xxx` -> 填描述 -> Create PR。
5. 审核通过合并后，同步并删分支：
   ```powershell
   git checkout main; git pull origin main; git branch -d feature/xxx
   ```
6. （可选，经张宗授权）代审：在他人 PR 上 Review（Approve / Request changes）。

> 注意：`main` 被保护，队长**不能直接 push 到 `main`**，必须走上面 PR 流程。

## 4. 杨文轩（队员B / 仓库协作者）

### 4.1 方式 A：直接在上游开发（推荐）
```powershell
git clone https://github.com/Archon0203/FPGA_Competition_HDMI.git
cd FPGA_Competition_HDMI
git config http.proxy  http://127.0.0.1:7890
git config https.proxy http://127.0.0.1:7890
git config user.name "杨文轩"; git config user.email "ywx324@users.noreply.github.com"
git checkout -b feature/xxx
# 改 src/ 与 sim/；sim_tb 跑 ModelSim 自检 PASS
git add -A; git commit -m "feat(display): add image_scaler"
git push origin feature/xxx
```
然后到原仓库：Compare -> base `main` <- compare `feature/xxx` -> Create PR。合并后同步删分支：
```powershell
git checkout main; git pull origin main; git branch -d feature/xxx
```

### 4.2 方式 B：fork 隔离（可选，分支更独立）
1. 原仓库 -> Fork 到自己的账号。
2. `git clone 你的fork` -> 配代理/身份；`git remote add upstream https://github.com/Archon0203/FPGA_Competition_HDMI.git`。
3. `git checkout -b feature/xxx` -> 改 -> 自检 PASS -> `git push origin feature/xxx`。
4. 到原仓库 New pull request -> base `main` <- compare **你 fork 的 feature/xxx** -> Create PR。
5. 同步上游：`git fetch upstream; git rebase upstream/main; git push --force-with-lease`。
6. 合并后：`git pull upstream main`；`git push origin --delete feature/xxx`。

## 5. 通用规范

- 分支：`feat/`（功能）、`fix/`（修复）、`docs/`（文档）、`refactor/`（重构）；一条 PR 只做一件事。
- 提交信息：`type(scope): subject`，如 `feat(framebuf): add async_fifo`。
- 必须过 ModelSim 仿真：新增/修改模块要带对应 `sim/tb_*.v`，自检输出 `PASS`；把结果贴到 PR 描述。
- 厂商 IP 不进仓库：PLL/SDRAM/HDMI 在 TangDynasty GUI 里例化，提交 `.v` 与 `constraints/`；`*.bit`、`*.db`、`*.area`、`sim_tb/`、`data/` 都已 gitignore。
- 大文件：图片/视频帧放 `data/`（默认不入库）；确需入库用 `git add -f 路径`，或改走 Git LFS。
- 冲突处理：先同步上游再改；冲突优先 `rebase`，解决后 `push --force-with-lease`。
- PR 描述建议：改动内容 / 影响模块 / 仿真结果(是否 PASS) / 是否需要上板验证。

## 6. 常见问题（FAQ）

| 问题 | 处理 |
|---|---|
| 连不上 github.com 443 | 配代理：`git config http.proxy http://127.0.0.1:7890`（再加 https.proxy） |
| `protected branch hook declined` | 正常：别直接推 main，改用 feature 分支再开 PR |
| 合并按钮灰 | 通常是未通过审批或还有未解决评论，先 Approve / resolve 再试 |
| 无法 push 到原仓库（403） | 确认已成为 Collaborator（Write）并接受邀请；或改用 fork 流程 |
| 想直推 main | 只有张宗（bypass）可以；其他人一律走 PR |
