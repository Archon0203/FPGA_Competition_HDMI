# M2 主从控制桥修复（2026-10-05）

## 修复原因

`m2_master_tf_hdmi_top` 原来复用 `m1abc_master_control_top`。
集成核对确认旧模块的 `catalog_valid/catalog_count` 同样连接真实 UART
coordinator，因此不能将“catalog 未连接”作为已经证实的故障根因。
本改动将 M2 控制独立包装，去除对旧本地诊断实例的依赖；功能验证见
[三线集成记录](M2_TEAM_INTEGRATION_20261005.md)。

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
