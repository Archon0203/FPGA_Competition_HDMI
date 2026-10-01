# M1 双板最小控制面验证实现记录

日期：2026-10-01

## 范围

本记录对应 M1 计划中的最小双板验证 profile，只验证两块 HX4S20C 的角色、GPIO 电平、方向、复位恢复和低速控制协议，不传输媒体像素，也不替代 SPI/source-synchronous 数据面验证。

角色划分：

- `master_top`：周期发送 `PING`、`OPEN`、`STATUS`、`ABORT`，接收从板回复；数码管状态位显示最近回复，计数位显示已发送帧数。
- `slave_top`：解析控制帧，返回 opcode 最高位置 1 的 ACK，并显示最近收到的命令和计数。

原 J1 方案在两块板上均表现为 TX 端排针恒高，未能形成可验证回环。物理连接改用 J2，按三根线执行：

```text
master J2-8 / K1 (uart_tx) -> slave J2-4 / G1 (uart_rx)
slave  J2-8 / K1 (uart_tx) -> master J2-4 / G1 (uart_rx)
master J2-12 -------------------- slave J2-12 (GND)
```

J2-4 对应 GPIOB_3/G1，J2-8 对应 GPIOB_7/K1。两端均使用 3.3 V LVCMOS；J2-11 是 5V，J2-12 是 GND。不要连接 5 V，也不要用 USB 线把两块 FPGA 当作 USB 通道互连。

## RTL 与工程文件

- 共享 UART/帧协议模块：`src/dual_board/db_uart_tx.v`、`db_uart_rx.v`、`db_frame_parser.v`、`db_frame_tx.v`。
- 角色顶层：`src/dual_board/dual_board_master_top.v`、`dual_board_slave_top.v`。
- 管脚约束：`dual_board/constraints/master.adc`、`slave.adc`。
- 上电复位：`src/dual_board/db_startup_reset.v`，默认保持约 20 ms；A2/KEY_1 仍提供低有效手动复位。
- 数码管：开发板为 8 位，`SEL0..SEL7` 分别绑定 F16、E16、E12、E10、C13、F10、E11、D11；旧版 6 位扫描遗漏 SEL0/SEL1，已在本次修复。
- 时序约束：`dual_board/constraints/m1_dual_board.sdc`。
- 可直接打开的 TD 工程模板：`validation/M1_dual_master.al`、`validation/M1_dual_slave.al`。
- 可供 TD 命令行复现的固定工程描述：`validation/M1_dual_master.prj`、`validation/M1_dual_slave.prj`。

顶层都使用 50 MHz `clk`、低有效 `rst_n`、`uart_tx/uart_rx` 和六位数码管输出。两块板的 ADC 均使用 F13 作为本地 TX、G14 作为本地 RX，外部连接交叉 TX/RX。

协议帧为零负载短帧：

```text
0x55 0xA5 opcode 0x00 crc8
```

CRC8 多项式为 `0x07`，覆盖 opcode；串口格式为 115200 baud、8N1。

## 仿真证据

命令：

```powershell
.\sim_tb\dual_board\run_dual_board.ps1
```

QuestaSim 10.7c 端到端回环 PASS：master/slave 完成 43 个接收帧和 42 个回复，PING/OPEN/STATUS/ABORT 均经过解析，UART framing error 与协议错误均为 0。

## TD 6.2.1 证据

命令：

```powershell
.\validation\run_m1_dual_board_td.ps1
```

该脚本分别执行 master、slave 的 synthesis、place、route 和 STA；两个角色使用独立运行目录和各自 ADC，不复用另一角色的 P&R 结果。

| 角色 | STA coverage | SWNS | STNS | HWNS | HTNS | violating endpoints |
|---|---:|---:|---:|---:|---:|---:|
| master | 98.66% | +14.109 ns | 0 ns | +0.214 ns | 0 ns | 0 |
| slave | 98.38% | +13.668 ns | 0 ns | +0.214 ns | 0 ns | 0 |

报告位置：`M1_Dual_master_Runs/phy_1/master_pr.timing`、`M1_Dual_slave_Runs/phy_1/slave_pr.timing`。

同一脚本已完成 BitGen，生成 `M1_Dual_master_Runs/phy_1/master.bit` 和 `M1_Dual_slave_Runs/phy_1/slave.bit`。实现后的 IO 报告确认两个角色均为 `uart_tx -> F13`、`uart_rx -> G14`，以及完整的 `seg_data/seg_sel` 管脚绑定。两个角色的 bitstream 必须按角色分别烧录，不能互换。

TD 仍会提示器件 speed 为空并自动采用默认 speed；该提示不影响本次路由和时序结果。当前证据是 `[C-sub]` 仿真和 `[S]` 独立角色实现，尚未取得两块实际开发板的 `[B]` 握手证据。

## 本轮硬件诊断更新

上板若观察到主板计数增加而从板计数保持不变，不能仅凭主板计数判断 UART 已经到达从板；主板计数代表发送调度请求。当前 RTL 已在 UART 接收器中增加起始位活动计数，并在两端状态位显示诊断码：`E0` 表示没有检测到 RX 起始位，`E2` 表示检测到电平活动但还没有完整有效帧，`E1` 表示 UART 或协议错误。计数位改为三位十进制，避免计数超过 9 后显示十六进制 A~F 字模。

本轮仿真仍通过；TD6.2.1 重新实现结果为 master SWNS `+12.413 ns`、HWNS `+0.230 ns`，slave SWNS `+13.919 ns`、HWNS `+0.214 ns`，两端 violating endpoints 均为 0。

若从板保持 `E0`，优先检查：Master J1-8/F13 是否真正接到 Slave J1-4/G14、Slave J1-8/F13 是否真正接到 Master J1-4/G14、J1-12 是否共地，以及线缆是否存在松动或接触电阻。若从板显示 `E2`，说明 RX 线上已有活动，应继续检查波特率、信号完整性和针脚方向。

## 上板顺序

1. 分别打开 master/slave 工程，确认 ADC 角色与板号对应，完整执行 synthesis、P&R、STA、BitGen。
2. 单板上电：master 未接从板时应保持复位后待发送状态；slave 应保持空闲状态。
3. 先接 GND，再接 TX→RX 和 RX→TX；不要接 5 V。
4. master 数码管计数增加且显示最近 ACK，slave 数码管计数增加且显示最近命令时，说明 M1 控制面握手通过。
5. 任意一板复位后，等待其重新上电并再次观察计数恢复；该结果只证明低速控制面，不证明媒体吞吐。





## 清理说明（2026-10-01）

本记录中的 `validation/`、`dual_board/constraints/` 与早期 `sim_tb/dual_board/` 路径属于 M1 bring-up 阶段的临时验证工程。M1ABC 真板闭环通过后，这些临时工程已从 GitHub 工作树清理；当前可复现入口统一为 `td_m1abc/` 与 `sim_tb/m1abc/`。本文件仅保留为历史开发记录，不应再按旧路径构建。
