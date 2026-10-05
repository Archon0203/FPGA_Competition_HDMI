# M2 连续加载与双板控制修复 · 2026-10-04

当前权威状态见 `../03_plan_and_status.md`。候选名：`M2_CONTROL_RELOAD_FIX_20261004`。本轮完成 RTL 修复、针对性回归及两角色实现；尚未烧录真板，不记新候选 `[B] PASS`。

## 1. 问题与修复

1. `p1_media_framebuffer_loader` 在注册的 `file_start` 尚未被下级消费时就读取旧 `file_done/parser_ok`，第二次加载可能提前结束或使用旧解析状态。忙状态处理跳过启动交接周期。用 HEAD 旧 loader 运行新增的多图用例，复现 9 项失败；修复后该用例 18 项通过。
2. Slave Top 的 `media_cmd_accept_ready` 在实例引用之后声明，TD 曾将它当成未驱动隐式线并把 dispatcher ready 固定为 0。改为实例前显式声明，后续 assign；最终综合已无此警告。
3. P1 scanout 已启动后，将 sticky `frame_ready` 拉低会停止预取但不会停止 scanout。现在首次成功后保持 ready，换图时隐藏单缓冲但继续扫描；当前事务成功且新 SDRAM fence 到达后，等待两个合格帧边界（排空一整帧旧预取）再显示。此 Top 级显示行为已通过实现，仍需真板确认。
4. Slave 在接收命令时锁存图片 ID；仅当前图片实际发布后报告 DONE。排队 OPEN 不再把上一图的 valid 当成新图 DONE，错误状态保持到下次事务。
5. Master 只接受四字节匹配响应与目标图片 DONE；READY/ACCEPTED 不表示完成。丢 OPEN/STATUS ACK 后保持事务串行，通过 STATUS 查询；截止周期收到有效响应优先处理。发现首图已显示时不重复加载启动图。
6. 自动轮播仅在控制器就绪且无积压切换意图时计时；加载期间清零，完成后重新停留 5 秒。取消已经绕回同一目标的陈旧延迟意图。dispatcher 同周期弹出旧请求、收到新请求时不丢新请求，同时遵守 valid/ready 的稳定 payload 契约。

未改 HDMI PHY/PLL、时序 profile、角色引脚约束或长期 `.al` 工程。Top 新增的仿真加速参数不改变生产默认值。

## 2. 验证证据

复现命令：`python tools/run_m2_control_regression.py`，需 Python 与 Questa 的 `vlib/vmap/vlog/vsim` 在 PATH。工作库及日志隔离到 `sim_work/m2_control_regression/`；脚本同时检查返回码和 FAIL/Error/Fatal 文本，避免 vsim 返回 0 掩盖失败。

| 用例 | 结果/覆盖 |
|---|---|
| media_command_controller | PASS 61；完成后计时、busy 不轮播、取消延迟意图 |
| coordinator realmedia | PASS 8；DONE 门控、丢 STATUS ACK 保持 busy |
| open dispatcher | PASS 7；稳定 pending payload 与排队 |
| real-media UART bridge | PASS 7；排队 OPEN 不误报旧 DONE |
| Master real-control link | PASS 13；真实 UART、独立 50/25 MHz 时钟，5 次 OPEN 无重叠、长加载、暂停、PREV/NEXT |
| real-media service | PASS 18；4 个不同文件/像素、同图重读、连续切图、坏 BMP |
| media-write CDC | PASS；5 次写、2 次 fence 的连续事务 |

这是单元/真实模块子链 `[U/C-sub]`，不是包含真实 SD、UART、vendor HDMI 的完整 M2 端到端仿真。

额外尝试旧 `sim_tb/m1abc/run_m1abc.do`，停在未改动的 `tb_m1b_spi_byte_loop.v`：`FAIL: M1B SPI byte loop master_rx=3c slave_rx=a5 valid=0`。接收数据符合预期，但 valid 检查未通过，原因尚未核实；不得将本轮结果表述为全仓 aggregate PASS。

| 角色 / Top | final STA 时间 | SWNS / HWNS | STNS / HTNS | coverage |
|---|---|---|---|---|
| Master / m1abc_master_control_top | 20:52:58 | +8.695 / +0.223 ns | 0 / 0 ns | 97.96% |
| Slave / m2_slave_tf_hdmi_top | 20:55:46 | +0.570 / +0.014 ns | 0 / 0 ns | 99.52% |

两角色 BitGen 成功；STA 结论限于当前约束所分析路径。Slave 仍有内部 SDRAM location 未采用及 local clock route 等工具警告，不代表全部实现警告清零。

原始证据在 [evidence/M2_CONTROL_RELOAD_FIX_20261004](evidence/M2_CONTROL_RELOAD_FIX_20261004/)：7 份回归日志、旧 loader 失败日志、最终 timing report、实现日志、源码与 bitstream SHA256 manifest。旧中间实现不能代替这里的最终报告。

## 3. 成对交付与板测步骤

输出目录：`sim_work/m2_control_fix_20261004/delivery/`。原角色 `_Runs` 未覆盖。

| 文件 | 字节 | SHA256 |
|---|---|---|
| master.bit | 629645 | c4399d2c054bfa0be349a5fbae342c2e925515c76e378a6466eb4649d265ef32 |
| slave.bit | 629641 | fb113670c2bf3dfaef75ff248d51fdedf599af16c4162080d5312484d5850224 |

1. 两块板分别烧录上述新 Master/Slave 文件，不能混用旧版本。TF 沿用已能出图的格式，至少准备 4 张肉眼明显不同的合规 640×480 BMP。
2. 先 Slave-alone：HDMI 接 Slave，复位后等待加载页转真实图片，观察至少 30 秒，不应自行反复加载。
3. 沿用已经验证的 TX/RX/GND UART 接线连接 Master，重新复位两板。此阶段 HDMI 仍接 Slave；Master 不输出 TF 图片。
4. KEY4 暂停自动播放，允许已开始的加载完成。KEY2 下一张、KEY3 上一张，每次等新图完整显示后再操作。完整正向、反向遍历至少 4 张，检查没有始终停在原图、跳错图或失去响应。
5. 快速按 NEXT/PREV 检查最终选择能收敛；忙时合并后续意图，不保证每次按键对应的中间图都显示。
6. KEY4 恢复轮播，观察至少 3 轮：每张实际可见后停留约 5 秒，再进入下一图加载。加载时间不计入停留时间。记录异常图编号、加载页颜色、LED 状态及是否可通过复位恢复。
7. 分别测试坏 BMP、控制链路中断与两板复位，并记录结果；这些故障的完整真板恢复验收尚未完成。

## 4. 当前限制与后续 M2 工作

- 仍是单缓冲，加载时会出现诊断/加载页。解决“总是原图”不等于无闪屏；保持旧图直至新图提交，需要后续双缓冲/安全 commit。
- 当前是 Master UART 控制 Slave 本地图像。TF 媒体跨板传输到 Master HDMI、高速数据面与最终 1080p 仍未完成。
- ACK 丢失不会提前释放 OPEN，但未加入完整 transaction-id/retry 与全局加载 watchdog。若 OPEN 本身丢失或设备重置后永远没有目标 DONE，可能持续 STATUS 查询；这是后续恢复门禁需处理的边界。
- 先通过本候选 Dual-control 板测，再继续 M2-B0 source-synchronous PRBS/CRC/sequence、真实 packet、Master RX/buffer/safe commit。M2 不在本轮关闭。
