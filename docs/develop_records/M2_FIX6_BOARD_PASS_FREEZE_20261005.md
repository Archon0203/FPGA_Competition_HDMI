# M2 FIX6 真板通过与阶段冻结（2026-10-05）

## 结论

当前阶段冻结为：

```text
M2_FIX6_BOARD_PASS_20261005
```

FIX6 修正 `link_data[3:5]` 的 J1 / FPGA 球位约束后，用户重新构建并上板确认：

- Slave 可读取 TF 卡内真实 640×480 / 24-bit BMP；
- 图片可通过当前 14 线双板链传到 Master；
- Master HDMI 可显示真实图片；
- NEXT / PREV 可正常切图；
- 自动轮播可工作；
- 先前“永久 Loading”和蓝屏问题已解除。

因此当前 640×480 静态图片双板基础闭环取得 `[B] PASS`。

## 根因归档

此前 FIX5 中 `link_data[3:5]` 的 FPGA 球位没有正确对应文档中的 J1-5/J1-6/J1-7。FIX6 固化为：

```text
link_data[3] -> J1-5 -> H13
link_data[4] -> J1-6 -> H14
link_data[5] -> J1-7 -> J14
```

该修复已由真板结果验证。

## 仿真与审计状态

本次用户运行全项目 audit 后：

- J1 electrical static audit PASS；
- `tb_m2_physical_pin_fault_signature` PASS；
- `tb_m2_full_frame_mailbox_640x480` PASS；
- 主要 M2 mailbox / remote-frame / storage 回归大部分 PASS；
- `framebuf/tb_p1_sdram_cached_adapter` 仍是当前 ACTIVE regression 的已知 FAIL；
- 另有若干历史/可选 testbench FAIL。

因此本阶段只冻结“真板基础功能 PASS”，**不宣称全仓 Questa 回归全绿**。

## 当前已知问题

1. **加载较慢**：图片切换等待明显长于官方样例，后续需要分段量化 TF、BMP、板间传输、SDRAM commit 各阶段耗时。
2. **Loading UI 体验**：当前切换时整屏显示 Loading；目标改为保留上一帧，只叠加小型加载提示。
3. **14 线带宽**：当前链路可用于静态图片验证，不作为后续持续视频传输方案。
4. **恢复与长稳**：异常卡、断链、单板复位、长时间轮播仍需正式门禁。
5. **仿真债务**：优先清理 `tb_p1_sdram_cached_adapter`，再整理历史/可选 TB。

## 下一阶段建议顺序

```text
1. 保留 FIX6 作为 rollback baseline
2. 测量并优化图片加载耗时
3. Loading 改为上一帧 + 小型 overlay
4. 清理 active SDRAM adapter regression
5. 做异常/复位/长稳
6. 再设计持续视频高速板间链路
```

本冻结不修改 `.git/` 内容。
