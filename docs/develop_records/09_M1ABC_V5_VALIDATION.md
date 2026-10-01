# 09 · M1ABC-v5 验证与关闭记录（2026-10-01）

## 1. 结论

M1ABC 的**真板可视化功能门禁已经 PASS**。本节点验证的是：

```text
Master/C 用户意图
 -> 115200 UART control frame
 -> Slave/A media-service contract
 -> image_id/status ACK
 -> frame-boundary config
 -> Slave HDMI_B 可视页面
```

它证明双板角色、GPIO 电气连接、双向控制协议、A 服务语义、C frame-boundary 提交与 HDMI 可视输出可以稳定闭环。它**不证明**最终 source-synchronous 媒体数据面，也不证明 1080p HDMI。

## 2. 已确认真板现象

固定接线：

```text
Master J1-8  (FPGA J13 / TX) -> Slave  J1-4  (FPGA F13 / RX)
Slave  J1-8  (FPGA J13 / TX) -> Master J1-4  (FPGA F13 / RX)
Master J1-12 (GND)            <-> Slave J1-12 (GND)
```

验证结果：

- Slave-alone：默认 deterministic 页面稳定输出；
- Dual：Slave HDMI 约每 2 s 在 4 个页面间轮播；
- Master KEY2=NEXT、KEY3=PREV、KEY4=PLAY/PAUSE 均能改变 Slave 屏幕；
- Slave 左上绿色 link 标记正常；fault 红条不出现；
- 两板 LED2 常亮、LED4 熄灭；activity toggle LED 可能表现为闪烁或较暗常亮；
- 用户确认整体行为“完全正常，一切如预期”。

因此记：

```text
M1ABC board functional gate [B] PASS
```

## 3. 已有控制链仿真证据

M1 之前的 v4 115200 framed UART 已在 QuestaSim 10.7c 通过：

```text
masks=1111/1111
master_err=0
slave_err=0
```

四种 opcode/ACK、CRC8 和两套独立时钟均通过，随后同一链路真板 PASS。

## 4. M1ABC aggregate Questa 状态

上一验证包的 `sim_tb/m1abc/run_all.bat` 在用户环境没有正常执行，因此**不得伪造 aggregate PASS**。本仓库已重写 `run_all.bat/run_all.do`：

- 使用与已成功 v4 脚本一致的 `vsim -c -do ... -l transcript...` 启动方式；
- 每个 RTL/TB 单独 `vlog`，避免 10.7c 对长多行命令/脚本错误处理的差异；
- 补回 `tb_m1c_frame_config_cdc`，统一执行 7 项门禁；
- 输出 `transcript_m1abc.txt`。

仍需在团队 Windows + QuestaSim 10.7c 环境补跑，才能记 aggregate `[C]`。

## 5. TD6.2.1 证据边界

两个角色工程：

```text
td_m1abc/M1ABC_MASTER_TD621/M1ABC_MASTER_TD621.al
td_m1abc/M1ABC_SLAVE_HDMI_TD621/M1ABC_SLAVE_HDMI_TD621.al
```

均已证明可打开、可综合、可生成并烧录 bitstream，且真板功能 PASS。由于当前对话没有提供两角色 final timing report 的具体 setup/hold 数值，本文件不把“BitGen/上板成功”自动写成完整 `[S]`。团队下一次本地构建应归档 final STA 摘要。

## 6. M1 临时角色与最终角色

M1 使用：

```text
Master control -> Slave HDMI
```

只是为了让显示器成为验证仪。最终产品冻结为：

```text
Slave: TF/FAT32/BMP/vseq -> media cache/prefetch -> packet source
Master: link RX -> line/tile buffer -> scaler/OSD/effects/audio -> 1080p HDMI
```

因此 M1 的 Slave HDMI 工程以后作为诊断/rollback 保留，不继续承载最终 1080p 主线。

## 7. M1 关闭与 M2 进入条件

已满足：

- 双板物理链 PASS；
- 115200 framed UART `[C-sub][B]` PASS；
- M1ABC board 可视化 `[B]` PASS；
- 两角色可独立生成 bitstream；
- Master 按键/自动轮播真实改变 Slave HDMI 页面。

待补档但不阻塞 M2 编码：

- 修复版 `run_all.bat` 的 7 项 aggregate Questa；
- Master/Slave final STA 数值归档；
- 可选断链/复位恢复完整记录。

当前节点转入 `docs/10_M2_REAL_MEDIA_ENTRY.md`。
