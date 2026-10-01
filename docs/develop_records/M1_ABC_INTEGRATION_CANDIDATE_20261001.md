# M1 ABC integration candidate — 2026-10-01

## 目标

在不等待真实 TF 和最终宽 GPIO 数据面的前提下，把 M1 的 A 服务语义、B 已真板通过的 UART 控制链、B packet/CRC/CDC 合同、C media command/frame-boundary 配置组合成一个可见的双板演示：Master 控制，Slave HDMI 显示。

## 已确认的先决证据

- 9600 UART minimum board link: PASS。
- 115200 UART framed link: Questa `masks=1111/1111` + board PASS。
- P1-04C 640×480 HDMI_B golden boundary: board PASS。
- M1A 原服务 shell/decoder/provider CDC 既有 Questa unit evidence。

## 新增 candidate

A:
- `src/storage/m1a_uart_service_bridge.v`

B:
- `src/dual_board/db_ctrl_frame_tx.v`
- `src/dual_board/db_ctrl_frame_parser.v`
- `src/dual_board/m1b_line_packetizer.v`
- `src/dual_board/m1b_line_packet_checker.v`
- `src/dual_board/m1b_packet_selftest.v`
- `src/dual_board/m1b_spi_master_byte.v`
- `src/dual_board/m1b_prbs_packet_tx.v`
- `src/dual_board/m1b_prbs_packet_rx.v`
- `src/dual_board/m1b_link_word_cdc.v`

C:
- `src/app/m1c_coordinator_uart.v`
- `src/app/m1c_frame_config_cdc.v`
- `src/display/m1c_axis_pattern_mux.v`
- `src/display/hdmi_1080p_raster.v`

Integration:
- `src/top/m1abc_master_control_top.v`
- `src/top/m1abc_slave_control_core.v`
- `src/top/m1abc_slave_hdmi_top.v`

## 证据边界

本记录不预填 PASS。发布包只能称为 candidate；需要用户依次提供：

1. `sim_tb/m1abc/run_all.bat` 全 PASS；
2. Master `.al` TD6.2.1 synthesis/P&R/STA/BitGen；
3. Slave HDMI `.al` TD6.2.1 synthesis/P&R/STA/BitGen；
4. Slave-alone HDMI 稳定；
5. 双板连接后 Master 控制 Slave pattern；
6. 断链/复位恢复。

1080p raster TB 只冻结逻辑 geometry，不证明 1080p PLL/PHY/board。
