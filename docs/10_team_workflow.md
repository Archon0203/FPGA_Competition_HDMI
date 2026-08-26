# 10 · 团队协作开发流程（GitHub + main 分支保护）

> 仓库：`Archon0203/FPGA_Competition_HDMI`（公开）
> 规则：对 `main` 的直接 push 被拒绝，一切改动必须走 PR，并经审核 + 1 个 Approve 后合并。
> 本文完整说明**初始设置**与**后续协作流程**，请每位成员先读一遍。

## 0. 团队成员与权限

| 角色 | 姓名 | GitHub 账号 | 仓库权限 | 职责 |
|---|---|---|---|---|
| **队员A**（仓库所有者） | 张宗 | `Archon0203` | **Owner** | 建仓、设分支保护、审核并合并 PR、维护 main 与文档 |
| **队长** | 曾雨婷 | `ZYT-zyt111` | **Collaborator（Write）** | 统筹、认领模块、开发、开 PR；经张宗授权可代审 |
| **队员B** | 杨文轩 | `ywx324` | **Collaborator（Write）** | 开发、开 PR；可直接在上游开发，也可 fork 隔离 |

> 三人都是仓库成员。**都禁止直接 push `main`**（受保护），一律走 feature 分支 + PR。队员B 有“直接在上游”和“fork 隔离”两种用法。

---

## 1. 初始设置（张宗 / Owner，已完成，供留存）

### 1.1 建仓库并推送
1. GitHub 上创建**公开**仓库 `FPGA_Competition_HDMI`（不要 Private；不要勾 README）。
2. 本地初始化并推送：
   ```powershell
   git init -b main
   git add -A
   git commit -m "init: project scaffold + docs"
   git remote add origin https://github.com/Archon0203/FPGA_Competition_HDMI.git
   git push -u origin main
   ```
3. 若连不上 GitHub，先配代理：`git config http.proxy http://127.0.0.1:7890`（再加 `https.proxy`）。
4. 确认身份：`git config user.name "张宗"`、`git config user.email "张宗邮箱@users.noreply.github.com"`。

### 1.2 设置 main 分支保护（Rulesets）
`Settings → Rulesets → New ruleset`，名称可 `Rule1`：
- **Target branches**：`Add target → Include by pattern → main`（关键！否则“targeting 0 branches”不生效）。
- **Branch rules** 勾选：
  - ✅ Require a pull request before merging → **Required approvals = 1**
  - ✅ Block force pushes
  - ✅ Require conversation resolution before merging
  - ❌ 不要勾 “Require status checks”（没有 CI）
- 底部点击 **Create / Save**。

### 1.3 把自己的账号加入 Bypass（避免自挡）
因为 ruleset 对**包括 Owner 在内**都生效，Owner 直推 main 也会被拦（“Changes must be made through a pull request”）。而 Owner 又**不能给自己的 PR 打 Approve**，所以给 Owner 加 bypass：
- 进入该规则edit → **Bypass list → Add bypass → Users → 选 `Archon0203` → Always allow → Save**。
- 之后你能直推 main（仅 Owner），队员仍被规则拦住，必须走 PR。

### 1.4 邀请队员为仓库成员（Write）
`Settings → Collaborators → Add people`：
- 添加 `ZYT-zyt111`（曾雨婷）与 `ywx324`（杨文轩），角色都选 **Write**。
- 两人各自打开 `https://github.com/invitations` **接受邀请**，才成为正式成员。

### 1.5 提交团队文档
把 `README.md`、`STRUCTURE.md`、`CONTRIBUTING.md`、`docs/10_team_workflow.md` 等提交并推送（这些是队员协作的依据）。

---

## 2. 通用前提（每位成员首次必做）

### 2.1 配置代理与身份
```powershell
git config --global http.proxy  http://127.0.0.1:7890   # 需要时可全局；或只对本仓库
git config --global https.proxy http://127.0.0.1:7890
git config user.name  "你的账号名"          # 如 ZYT-zyt111 / ywx324
git config user.email "你的邮箱@users.noreply.github.com"
git config --list      # 确认生效
```
> 若只想本项目生效，去掉 `--global`，在仓库目录内执行。

### 2.2 克隆原仓库
```powershell
git clone https://github.com/Archon0203/FPGA_Competition_HDMI.git
cd FPGA_Competition_HDMI
```

### 2.3 仿真自检（ModelSim）
在 `sim_tb` 目录运行：
```powershell
cd sim_tb
vsim -c -do ../sim/run_vga_timing.do
```

---

## 3. 张宗（队员A / 仓库所有者 / 审核者）

### 3.1 日常审核与合并
1. 打开仓库 `pulls` 看待审 PR。
2. 进入 PR：`Files changed` 看 diff → 留评论 → `Review`：
   - 没问题 → **Approve**；
   - 有问题 → **Request changes**（写明改法）。
3. 通过后 **Merge pull request（Squash and merge）** → 删除源分支。
4. 同步本地：`git checkout main; git pull origin main`。

### 3.2 自己开发
```powershell
git checkout -b feature/xxx
git add -A; git commit -m "feat(module): desc"
git push origin feature/xxx
```
再在 GitHub 上 base `main` <- compare `feature/xxx`，Create PR（自己审或让曾雨婷审）。

---

## 4. 曾雨婷（队长 / 仓库协作者 / 统筹）

1. 已接受做协作者邀请（见 §1.4）。
2. 首次克隆 + 配置（见 §2）。
3. 开发：
   ```powershell
   git checkout -b feature/xxx
   # 修改 src/ 与 sim/；在 sim_tb 跑 ModelSim 自检 PASS
   git add -A; git commit -m "feat(framebuf): add async_fifo"
   git push origin feature/xxx
   ```
4. 提 PR：GitHub → Compare → base `main` <- compare `feature/xxx` → Create PR。
5. 审核通过合并后：`git checkout main; git pull origin main; git branch -d feature/xxx`。
6. （经张宗授权）可代审：在他人 PR 上 Approve / Request changes。

---

## 5. 杨文轩（队员B / 仓库协作者）

### 5.1 方式 A：直接在上游开发（推荐）
同队长：克隆原仓库 → 配代理/身份 → 建分支 → 改 → 自检 PASS → `git push origin feature/xxx` → 开 PR → 合并后清理。

### 5.2 方式 B：fork 隔离（可选）
1. 原仓库 → **Fork** 到 `ywx324` 名下。
2. `git clone https://github.com/ywx324/FPGA_Competition_HDMI.git`
   `git remote add upstream https://github.com/Archon0203/FPGA_Competition_HDMI.git`
3. `git checkout -b feature/xxx` → 改 → 自检 → `git push origin feature/xxx`。
4. 到原仓库 New pull request → base `main` <- compare **`ywx324/fork:feature/xxx`** → Create PR。
5. 同步上游：`git fetch upstream; git rebase upstream/main; git push --force-with-lease`。

---

## 6. 通用规范

- 分支：`feat/`（功能）、`fix/`（修复）、`docs/`（文档）、`refactor/`（重构）；一条 PR 只做一件事。
- 提交信息：`type(scope): subject`，如 `feat(framebuf): add async_fifo`。
- 每个 `src/` 模块必须带对应 `sim/tb_*.v`，仿真自检输出 `PASS`，结果贴到 PR。
- 厂商 IP 不进仓库：PLL/SDRAM/HDMI 在 TangDynasty GUI 例化，提交 `.v` 与 `constraints/`；`*.bit`、`*.db`、`*.area`、`sim_tb/`、`data/` 已 gitignore。
- 大文件：图片/视频帧放 `data/`（默认不入库）；个别用 `git add -f 路径`，或改走 Git LFS。
- 冲突：先同步上游再改；优先 `rebase`，解决后 `push --force-with-lease`。
- PR 描述：改动内容 / 影响模块 / 仿真结果(是否 PASS) / 是否需要上板验证。

---

## 7. 常见问题（FAQ）

| 问题 | 处理 |
|---|---|
| 连不上 github.com 443 | 配代理：`git config http.proxy http://127.0.0.1:7890`（+ https.proxy） |
| push 到 main 被拒 “protected branch hook declined” | 正常：别直接推 main，建 feature 分支再开 PR |
| Owner 也被 main 规则挡住 | 在规则 **Bypass list** 加入 `Archon0203`；或临时把 Enforcement 设为 Disabled，推完改回 Active |
| 队员 push 到原仓库被拒（403） | 先让他们接受邀请（`github.com/invitations`），确认已是 Collaborator(Write) |
| 合并按钮灰 | 未通过审批或还有未解决评论；先 Approve / resolve |
| fork 的 PR 分支选错 | compare 选自己 fork 的分支，base 是原仓库 `main` |
