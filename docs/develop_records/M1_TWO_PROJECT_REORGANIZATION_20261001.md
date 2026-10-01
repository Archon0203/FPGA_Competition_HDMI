# M1 两工程 / 共享 RTL 重构记录（2026-10-01）

## 目的

消除 `FPGA_Competition_HDMI.al`、M1 Master 工程、M1 Slave 工程三者并存造成的构建歧义，并固定后续 M2~M6 的长期工程入口。

## 结果

当前工作树只保留两个 `.al`：

```text
FPGA_Competition_HDMI_MASTER.al
FPGA_Competition_HDMI_SLAVE.al
```

- Master 当前 Top：`m1abc_master_control_top`。
- Slave 当前 Top：`m1abc_slave_hdmi_top`。
- 两个工程直接引用仓库根目录 `src/`，不再保存角色本地 RTL 副本。
- Master 只加载 `constraints/master/master.adc`、`constraints/master/master.sdc`。
- Slave 只加载 `constraints/slave/slave.adc`、`constraints/slave/slave.sdc`。
- P1-05A rollback 的源码和历史证据保留，但旧 rollback `.al` 被移除；如需追溯可使用 Git 历史。

## 共享源码基线

原 M1ABC 两个可上板工程与根 `src/` 比对时，仅 `db_uart_tx.v` 存在文本差异。为保证新共享工程继承真板通过实现，已将 **M1ABC 真板工程使用的 `db_uart_tx.v`** 提升为 `src/dual_board/db_uart_tx.v` 的 canonical 版本；其余角色本地 RTL 与根 `src/` 对应模块一致。

## 已清理

- `td_m1abc/`（角色本地 RTL/约束副本）；
- 旧根 `FPGA_Competition_HDMI.al`；
- 早期 `dual_board/` 和 `sim_tb/dual_board/` bring-up 工程；
- `sim_work/`、`*_Runs/`、`log/`、`work/` 等本地生成物；
- bring-up 专用 `dual_board_*_top`、旧 `db_frame_*`、`db_hex_display`、`m1a_validation_top`；
- `docs/evidence/` 重复入口（规范位置仅为 `docs/develop_records/evidence/`）。

## 验证状态

重构前 M1ABC aggregate Questa 已由实测返回：

```text
Errors: 0, Warnings: 0
```

M1ABC 双板真板控制/HDMI 闭环也已 PASS。此次重构不改变功能 RTL 拓扑，只把已经验证过的角色工程 Source_Files 指向 canonical `src/`。新 `.al` 仍需在本机 TD6.2.1 分别执行 synthesis → P&R → STA → BitGen，作为工程路径重构后的最终 `[S]` 复核。

## 后续纪律

1. 不再新增第三个 active `.al`。
2. 不在 TD 角色目录复制 RTL。
3. 修改共享模块时，评估并重新构建所有引用该模块的角色工程。
4. Master/Slave 约束严格分离。
5. 构建记录、STA、真板证据继续放在 `docs/develop_records/` / `docs/develop_records/evidence/`。
