# 文档状态与目录规范清理记录（2026-10-04）

> 本文件是开发过程记录，不是当前状态权威。当前状态只以 `docs/03_plan_and_status.md` 为准。

## 1. 清理目的

本次只整理文档，不修改 RTL、约束、TD 工程、仿真脚本或工具代码。目标是消除“历史候选/阶段推断被误读为当前 PASS”的问题，并恢复统一文档目录规范。

## 2. 当前状态纠正

统一修正以下口径：

- M1 deterministic/mock 双板控制门禁已经关闭，但不能继承为 M2 真实 TF 媒体切换 PASS；
- M2 已取得 `TF -> FAT32/BMP -> Slave SDRAM -> Slave 640×480 HDMI` 的本地真板子门禁；
- 真实媒体双板 NEXT/PREV、PLAY/PAUSE、自动轮播当前**未通过**；
- DUALCTRL2 的 `OPEN -> ACCEPTED -> STATUS -> DONE` 是修复候选，不是已验证结论；
- FIX1 只修复了 `source_valid` 接口遗漏，尚需重新综合、Questa、final STA 和真板验证；
- source-synchronous 高速媒体数据面、Master-owned 最终媒体显示和 1080p 均未完成。

## 3. 权威文件

`docs/03_plan_and_status.md` 是唯一进度/证据状态权威。其他文件承担架构、目标、演示、A/B/C 计划或过程记录职责，不得自行升级 PASS 等级。

指定阶段入口保留为：

```text
docs/develop_records/M1ABC_V5_VALIDATION.md
docs/develop_records/M2_REAL_MEDIA_ENTRY.md
```

删除重复别名 `09_M1ABC_V5_VALIDATION.md` / `10_M2_REAL_MEDIA_ENTRY.md`，避免同一记录存在两个不同版本。

## 4. 目录清理

- `docs/` 根目录只保留 `01~08` 规范文档以及 `develop_records/`、`olds/` 子目录；
- 原 `docs/evidence/` 内容与 `docs/develop_records/evidence/` 完全重复，因此删除重复入口；
- 根目录阶段 `CHANGESET_20261004*.md` 迁移至 `docs/develop_records/`；
- 日志、截图、报告继续统一放入 `docs/develop_records/evidence/`。

## 5. 证据边界

旧版本的 routed STA、area 或真板 PASS 继续作为对应旧候选的历史证据，但不得自动赋给后续 RTL。特别是已归档的 M2 `SWNS +0.659 ns / HWNS +0.014 ns` 与 `LUT 13133/19600` 对应较早诊断实现，不是 DUALCTRL2 FIX1 的实现证据。
