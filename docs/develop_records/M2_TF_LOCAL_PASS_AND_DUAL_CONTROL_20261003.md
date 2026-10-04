# M2 TF 本地图像真板 PASS 与双板控制接入（2026-10-03）

> **开发过程/候选记录：保留当时的现象、推断和修复方案，不作为当前 PASS 状态权威。当前状态以 `docs/03_plan_and_status.md` 为准。**


## 1. 本轮真板结论

M2 Slave 的真实 TF/FAT32/BMP 本地图像链已经取得首次真板可观察 PASS：

```text
TF card -> SPI -> FAT32 catalog -> BMP RGB24 -> write CDC
        -> APUG011 internal SDRAM -> framebuffer scanout -> HDMI
```

用户真板现象：

1. 插入 TF 卡后复位/烧录；
2. HDMI 先显示黄色加载页；
3. 随后成功显示 TF 卡中的 640x480 BMP 图片；
4. 拔掉 TF 卡后复位显示红色 fault 页；
5. 重新插卡并复位可再次正常显示图片。

因此可记录：

```text
M2 real TF/FAT32/BMP local 640x480 image path [B] PASS
```

该结论只覆盖 Slave 本地 640x480 BMP 图片读取和 HDMI 显示，不等价于双板高速媒体数据面、1080P、视频或 UI 完成。

## 2. 关键根因关闭

真板此前稳定进入 `0x11` sector-read failure。DIAG5 修正 `sd_reader.v` 中 CMD17 的最后命令字节：

```text
错误：... 00   (end bit = 0)
修正：... 01   (end bit = 1)
```

SD SPI 命令帧固定 end bit 必须为 1。原仿真 card model 未检查该位，因此此前的 CMD17 snapshot regression 可出现“仿真 PASS、真卡拒绝”的假阴性。DIAG5 同步在仿真模型中加入 command end-bit 检查。

该修复后真板首次成功输出 TF 卡 BMP，故 CMD17 帧格式错误被视为本轮 TF 读取失败的已验证主要根因。

## 3. 成功显示后仍出现的 LED/fault 现象

成功显示图片后观测：

```text
4-LED group:
  LED1 = ON
  LED2 = blinking
  LED3 = dim ON
  LED4 = ON

8-LED group:
  LED6, LED7, LED9, LED10, LED11 = ON
```

按 8 灯映射，该组合为 `0x3B`。因为图片已经在此前成功显示，所以该 `0x3B` 不是第一次加载失败，而是成功后又启动了后续加载事务。

代码审查确认 `m2_slave_tf_hdmi_top` 的 standalone 自动加载逻辑存在重复触发：每次 `media_done` 后旧逻辑会再次自动发 `OPEN(0)`，造成 image0 无限重载；这会抢占/掩盖 Master 的 NEXT/PREV/轮播命令，也能解释 LED2 周期活动、LED3 亮度偏暗和后续 `0x3B` fault。

## 4. 双板控制修复

新增：

```text
src/dual_board/m2_open_dispatcher.v
```

职责：

- catalog 首次可用后只自动发 **一次** standalone `OPEN(0)`；
- 该 bootstrap 完成后，不再自行循环重载 image0；
- Master 的远程 `OPEN(image_id)` 成为后续换图唯一正常命令源；
- media busy 时保留一个 pending remote OPEN，新的用户选择覆盖旧 pending 选择（latest selection wins）；
- no-card/fault 自动重新扫描时，通过 `catalog_restart` 重新 arm 一次 bootstrap，以保留“插卡后重试可恢复”的能力。

Slave TD 工程 `FPGA_Competition_HDMI_SLAVE.al` 已加入该 RTL。

同时修复 `src/framebuf/m2_media_write_cdc.v` 的重复事务 fence：旧实现将 `media_done`/`sdr_fenced` 永久锁存，适合首帧 bring-up，但第二次 OPEN 开始后 `sdr_fenced` 仍为 1，会让 `frame_ready_sdr` 过早重新发布正在覆盖的单 framebuffer。当前改为 **每个 media_done 一个 toggle token、每个事务一个 one-cycle `sdr_fenced` pulse**，并在 media domain 等待上一帧真正 `frame_ready_sdr` 后才允许 post-success 的下一条 OPEN 被 media service 接受。该修复是 NEXT/PREV/轮播正确性的必要条件。

## 5. Master 控制约定

Master 继续使用已真板验证的三线 UART 控制面：

```text
Master J1-8 / FPGA J13 / TX -> Slave J1-4 / FPGA F13 / RX
Slave  J1-8 / FPGA J13 / TX -> Master J1-4 / FPGA F13 / RX
Master J1-12 / GND           <-> Slave J1-12 / GND
```

不要连接两板 5 V。

Master 当前按键：

```text
KEY2 = NEXT
KEY3 = PREV
KEY4 = PLAY / PAUSE
```

`media_command_controller` 默认 `play_en=1`，`SLIDE_PERIOD_CLKS=100_000_000`，在 50 MHz Master clock 下约 2 s 自动轮播一次。Catalog count 来自 Slave 的真实 FAT32 catalog；Master 通过 `m1c_coordinator_uart` 发 `OPEN(image_id)`，Slave 通过 `m2_real_media_uart_bridge` 接收并排队。

## 6. 预期静止状态

修复重复 bootstrap 后，Slave 独立加载 image0 成功且无 Master 新命令时，预期：

```text
4 灯：LED1 + LED3 常亮；LED2 + LED4 灭
8 灯：build marker 0x81 -> LED6 + LED13 亮
HDMI：保持当前 BMP，不再周期性重载
```

接入 Master 后，按 NEXT/PREV 或自动轮播时 LED2 可在真实 TF load 期间亮/闪，完成后再次回到静止状态。

## 7. 仿真门禁

新增：

```text
sim_tb/m1abc/tb_m2_open_dispatcher.v
sim_tb/m1abc/run_m2_open_dispatcher.do
sim_tb/m1abc/run_m2_open_dispatcher.bat
```

覆盖：

1. catalog 建立后只产生一次 bootstrap `OPEN(0)`；
2. bootstrap 不会自行重复；
3. remote OPEN 可在 bootstrap 后正常发出；
4. busy 时 latest remote selection wins；
5. catalog restart 后重新允许一次 bootstrap。

此外更新 `sim_tb/storage/tb_m2_media_write_cdc.v`，要求连续两次 media transaction 各自产生一次 fence，且 fence 不得 sticky。

当前交付环境没有 QuestaSim 10.7c 可执行程序，因此该新增 TB 必须在项目 Windows/Questa 环境实际运行后才能记 `[U] PASS`，不得在文档中虚报。

## 8. 时序与资源

最近已归档的 routed STA（DIAG4）为：

```text
SWNS +0.659 ns
STNS 0.000 ns
HWNS +0.014 ns
HTNS 0.000 ns
```

最新已归档 area（DIAG4）为：

```text
LUT  13133 / 19600 = 67.01%
REG   7227 / 19600 = 36.87%
BRAM9K 10 / 64
BRAM32K 0 / 16
```

DIAG5 + 本次 dispatcher 修改后的最终 STA/area 尚未在仓库归档，因此本候选仍要求分别重新跑 Master/Slave TD synthesis -> P&R -> final STA -> BitGen。

资源后续重点仍是把 `line_buffer_pingpong` 从约 4.7k LUT 的实现迁移到真正 BRAM；在 TF/双板控制闭环稳定前，本轮不同时重构该显示数据通路。

## 9. 当前状态边界

已完成：

```text
[M2-A local board] real TF/FAT32/BMP 640x480 -> Slave SDRAM -> Slave HDMI [B] PASS
[M1 control]       115200 framed UART two-board control baseline [B] PASS
```

本候选待验证：

```text
Master real catalog discovery
Master KEY2 NEXT / KEY3 PREV
Master KEY4 PLAY/PAUSE
~2 s automatic carousel
Slave one-shot standalone bootstrap (no repeated OPEN0)
```

仍未完成：

```text
source-synchronous high-speed media data plane
Master-owned final framebuffer/HDMI path
720p/1080p real media
video / UI / OSD final integration
```
