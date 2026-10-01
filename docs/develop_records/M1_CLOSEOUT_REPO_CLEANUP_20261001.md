# M1 closeout / repository cleanup — 2026-10-01

## 结论

- M1ABC aggregate Questa：PASS（`Errors: 0, Warnings: 0`）。
- M1ABC 双板真板可视化：PASS。
- `docs/08_three_line_integration_flow.md` 恢复原有 Mermaid M0～M6 三线流程图，并仅在原流程图基础上更新 M1/M2 状态。
- `docs/` 根目录恢复为 01～08 规范文档；开发记录统一放入 `docs/develop_records/`。
- 原 `docs/evidence/` 已迁移为 `docs/develop_records/evidence/`。

## 清理的过期 bring-up 文件

以下内容已经由 M1ABC 当前工程替代，因此从工作树删除：

- `validation/`：早期 M1 UART / GPIO probe / internal-loop TD 临时工程；
- `dual_board/`：早期独立约束和 README；
- `sim_tb/dual_board/`：旧 UART bring-up testbench；
- `src/dual_board/dual_board_*_top.v`：早期 probe/master/slave top；
- `src/dual_board/db_frame_tx.v`、`db_frame_parser.v`、`db_hex_display.v`：仅服务于旧 top 的协议/显示模块；
- `src/storage/m1a_validation_top.v`：早期 M1A 验证 top。

保留当前有效入口：

- `sim_tb/m1abc/`；
- `td_m1abc/M1ABC_MASTER_TD621/`；
- `td_m1abc/M1ABC_SLAVE_HDMI_TD621/`；
- `src/dual_board/db_uart_*`、`db_ctrl_frame_*`、`m1b_*` 当前公共 RTL。

## Git 处理规范

发布 ZIP 不包含 `.git/`，因此不会携带或覆盖 branch、remote、index、HEAD、hooks 等仓库元数据；保留 `.gitignore` 和 `.gitattributes`。生成物、bitstream、Questa `work/`、TD run 目录和 minidump 不进入发布包。
