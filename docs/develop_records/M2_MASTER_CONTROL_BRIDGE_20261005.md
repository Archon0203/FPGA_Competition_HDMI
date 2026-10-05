# M2 主从控制桥修复（2026-10-05）

## 修复原因

`m2_master_tf_hdmi_top` 原来只例化了 M1 演示用的
`m1abc_master_control_top`。该模块内部的 `catalog_valid` 没有连接真实从板
UART 状态，因此主板 HDMI 接收链虽然存在，主板按键却不能稳定地产生真实
`OPEN(image_id)`。

## 当前实现

新增 `src/dual_board/m2_master_media_control.v`，连接关系为：

```text
主板 KEY2/KEY3/KEY4
    -> key_filter
    -> media_command_controller
    -> m1c_coordinator_uart
    -> framed UART
    -> 从板 m2_real_media_uart_bridge
```

`m1c_coordinator_uart` 只在从板 PING 返回 catalog 后开放命令；OPEN 的
`ACCEPTED` 不作为完成，继续 STATUS 轮询到目标图片真正 DONE。主板 UART
控制面与 7-bit REQ/ACK 图片数据面同时保留，主板 HDMI 仍由
`m2_master_tf_hdmi_top` 独占。

## 验证

- 新控制模块依赖编译：ModelSim 10.6d `vlog` PASS，无 error/warning。
- 主/从 top 相关 RTL 编译：`m2_master_tf_hdmi_top`、`m2_slave_tf_hdmi_top`、
  `m2_frame_display_core` 及新控制桥编译 PASS。
- TD 工程 source path/CRLF 检查 PASS；新模块已加入两份长期 `.al` 工程。

## 板测接线

沿用 `M2_MASTER_OUTPUT_20261004.md` 的 14 根线：UART 两根交叉、7 根
`link_data`、REQ、ACK、`display_published` 和两根 GND。两块板必须同时更新
bitstream，并从复位初态开始测试；HDMI 接主板，TF 卡留从板。
