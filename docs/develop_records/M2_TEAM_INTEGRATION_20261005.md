# M2 三线提交集成 · 2026-10-05

当前进度权威为 `../03_plan_and_status.md`。本次新候选尚未上板，不能继承旧拓扑的 `[B]`。

## 合入范围

- 从干净的 `feature/dual-board-connect@d472dc8` 创建 `codex/m2-team-integration-20261005`。
- fast-forward 到 `origin/main@ad9ed23`，包含曾雨婷 PR #39（`cb737e8`）及杨文轩 PR #38（`ad9ed23`）。没有文字合并冲突。
- fetch 后 `origin/docs/upgrade` 与 main 的文件树相同，无额外未集成代码需要重复合并。
- 保留 A 的真实媒体传输 smoke test、B 的独立 `m2_master_media_control` 及 Master Top 接入。物理接口、14 线 pin map、TF SPI 速率、HDMI profile 不变。

## 发现并修复的集成问题

1. 两份 TD 工程带入多处 `AutoExcluded=true`，包括 active Top 依赖。清除 GUI 排除缓存，由综合从 Top 计算可达模块；升级工程检查器，检查所有文件是否存在及 AutoExcluded，不再只检查 async_fifo 的 UsedInSyn。注入排除标记的反例验证返回失败。构建脚本入口也先执行检查。
2. 新 `tb_m2_real_media_remote_link` 将媒体发送器的 `wr_ready` 与 mailbox 的 `in_ready` 都接到 `frame_ready`，出现多驱动，并误把两级背压视为同一信号。拆分为 service ready 与 mailbox ready，补充接收像素值、BMP 行方向断言和 watchdog。修正后 4 项检查通过。
3. 同事的新 smoke test 替换了原 18 项多文件测试。保留新测试，同时将旧测试另存为 `tb_m2_real_media_remote_multiframe`，防止同图重载、多图切换、坏 BMP 的覆盖消失。
4. 原控制链测试仍例化旧 M1 Top，未覆盖当前 Master 实际使用的独立控制模块。给新模块增加默认值不变的 POR 参数，并新增真实 UART/异步双时钟控制回归，验证慢加载串行、自动轮播、物理暂停、NEXT/PREV。
5. 新控制桥记录曾称旧 M1 Top 没有连接真实 catalog。源码核对表明旧模块的 catalog 同样来自 UART coordinator；新模块价值是独立控制包装、去除旧本地诊断实例，不应将未证实的断线作为修复根因。已更正文档与模块说明。

## 验证及可复现命令

```powershell
python tools/check_td_project.py
python tools/run_m2_control_regression.py
python tools/build_m2_roles.py --output sim_work/m2_team_integration_20261005
```

14 项 `[U/C-sub]` 全通过：原控制/调度/CDC/CRC/显示测试、新旧控制 wrapper、A 新 smoke、多文件媒体链、加载页和 BRAM 行缓存。不是 vendor HDMI 完整端到端仿真，也不是整个仓库所有历史回归。

| 角色 | Top | LUT | SWNS | HWNS | STNS / HTNS |
|---|---|---:|---:|---:|---|
| Master | m2_master_tf_hdmi_top | 4386 | +0.670 ns | +0.003 ns | 0 / 0 |
| Slave | m2_slave_media_tx_top | 6114 | +10.085 ns | +0.075 ns | 0 / 0 |

两角色均完成 synthesis → P&R → final STA → BitGen，检查构建前后源码哈希一致。STA 结论仅覆盖当前约束；vendor 宏警告仍存在，不宣称零 warning。板外连线与信号完整性仍需真板验证。

证据：[evidence/M2_TEAM_INTEGRATION_20261005](evidence/M2_TEAM_INTEGRATION_20261005/)（仿真日志、实现日志、area/timing、源码及 bit SHA256 manifest）。

## 成对烧录与下一步

交付目录：`sim_work/m2_team_integration_20261005/delivery/`。旧交付目录未覆盖。

- `master.bit` SHA256：`a99e596c49015ba0c2e2daf2ebe7ccd4a8f0352a3d50f0a6d7168c4af8a0c554`。
- `slave.bit` SHA256：`d8a3d0cef9ebe29bf7d5c8a5bd1dcecab59a24c65df923a0105943b16ae31eba`。

沿用 [14 线表](M2_MASTER_OUTPUT_20261004.md)，两板一起更新，HDMI 接 Master、TF 留 Slave。一起按住复位，先松主板后松从板；验证加载卡→第一图，KEY4 暂停后 KEY2/KEY3 遍历至少四图，再恢复自动轮播。记录故障 LED、错误页及两板复位后的行为。

本轮只做已有三线提交的集成与修复。仍是 640×480 单缓冲、带确认的低速图片传输；1080p、高速视频、双缓冲无闪屏、完整断链恢复尚未关闭。未 push、未发布 PR、未烧录真板。
