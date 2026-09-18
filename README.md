# 基于 EG4S20 的 HDMI 多媒体播放系统

> 2026 全国大学生嵌入式芯片与系统设计竞赛 · FPGA 创新设计赛道 · 安路选题一  
> 平台：HX4S20C / EG4S20BG256  
> 开发工具：Anlogic TD 6.2.1；QuestaSim 10.7c

## 当前稳定基线

**P1-05A 已完成并正式关闭：internal SDRAM framebuffer → HDMI_B 已取得仿真、TD timing、BitGen 和真板证据。**

当前 active build：

```text
Project : FPGA_Competition_HDMI.al
Device  : EG4S20BG256
TOP     : p1_hx4s20c_sdram_hdmi_top
ADC     : constraints/p1_hx4s20c_hdmi_board.adc
SDC     : constraints/p1_hx4s20c_hdmi_board.sdc
```

当前真板稳定显示固定 SDRAM framebuffer：四周白边、红/绿/蓝/黄四象限、中央洋红竖条和青色横条。最终 BitGen 上板后画面持续稳定，无可见抖动、抽搐、撕裂或移动黑线。

P1-04C 八色条仍保留为 HDMI golden rollback；P1-05A 则是当前 **framebuffer golden baseline**。

> **TD6.2.1 migration note (2026-09-17):** 官方要求已切换到 TD6.2.1。旧 source baseline 的报告曾出现 routed `HWNS=+0.011 ns`、`SWNS=-7.098 ns`，150 MHz 同域 `SWNS=-1.119 ns / HWNS=+0.182 ns`。当前源代码保留 production 版诊断逻辑裁剪，并将 HDMI reset 释放恢复为官方例程使用的 50 MHz 上升沿；下降沿实验会使 125 MHz serial-domain recovery 变差。**这些修改仍需在本地 TD6.2.1 重新 P&R/BitGen 验证，不能把历史结果标成新的 `[S]` 或 `[B]` 证据。**

## P1-05A 证据摘要

### QuestaSim

```text
p1_framebuffer_pattern_writer     PASS(259)
p1_sdram_read_cdc_bridge          PASS(13)
hdmi_framebuffer_scanout          PASS(35)
p1_sdram_hdmi_pipeline            PASS(258)
p1_sdram_cached_adapter           PASS(58)
p1_sdram_hdmi_cached_chain        PASS(260), pixels=256, underflow=0
cached adapter + official APUG011 PASS(24)
```

最终 cached-adapter 单测确认：

```text
abstract_reads=8
app_reads=8
hits=6
misses=2
```

official APUG011 compatibility 确认：两次 abstract read 均被正确接受，读回 `addr=5 -> 0x11223344`、`addr=8 -> 0xA5A55A5A`，并保持 tCK/tRCD/DQM/protocol health 全部 PASS。

### TD5.6.2 combined timing

```text
Timing violations : 0 setup / 0 hold
Setup WNS         : +0.068 ns
Setup TNS         : 0.000 ns
Hold WHS          : +0.131 ns
Hold TNS          : 0.000 ns
STA coverage       : 98.69%
```

各时钟域：

| Clock | Target | Min Period | Max Freq | TNS |
|---|---:|---:|---:|---:|
| HDMI pixel | 25 MHz | 27.015 ns | 37.000 MHz | 0 |
| SDRAM | 150 MHz | 6.598 ns | 151.561 MHz | 0 |
| board | 50 MHz | 6.770 ns | 147.710 MHz | 0 |
| HDMI serial | 125 MHz | 7.177 ns | 139.334 MHz | 0 |

**注意：P1-05A 虽已 `[S] PASS`，但 150 MHz 关键裕量只有约 68 ps，属于“已闭合但余量较薄”。后续任何 RTL、约束或布局变化都必须重新跑完整 STA，不能继承本次正裕量。**

### Post-Phy 资源

```text
LUT      9977 / 19600 = 50.90%
REG      2825 / 19600 = 14.41%
BRAM9K     10 / 64    = 15.62%
BRAM32K     0 / 16    = 0%
DSP         1 / 29
PLL         2 / 4
GCLK        2 / 16
```

line buffer 的 block-RAM 映射仍有优化空间；此前仅添加 `ram_style` 并未显著改变 BRAM 数量。该项作为后续资源优化任务保留，不阻塞 P1-05A 关闭，但 P1-05B 加入 TF/FAT32/BMP 前后必须持续监控 LUT 与 timing margin。

## 当前数据链

```text
50 MHz board clock
├─ HDMI PLL -> 25 MHz pixel / 125 MHz serial
│   └─ P1-04C free-running raster / APUG092 / HDMI PHY / HDMI_B
│
└─ 25 MHz -> APUG011 PLL -> 150 MHz / shifted SDRAM clocks
      ↓
p1_framebuffer_pattern_writer
      ↓
sdram_arbiter
      ↓
p1_sdram_cached_adapter
      ↓
official APUG011 + EG_PHY_SDRAM_2M_32
      ↓
internal SDRAM
      ↓
p1_sdram_read_cdc_bridge (150 ↔ 25 MHz)
      ↓
line_prefetcher
      ↓
line_buffer_pingpong
      ↓
hdmi_framebuffer_scanout
      ↓
axis_data mux
      ↓
P1-04C APUG092 / HDMI_B golden boundary
```

关键工程修复：

- sequential-read 4-word cache 消除了 P1-02 random-word adapter 在视频连续读取下的重复 APUG011 group 开销；
- prefetch 仅在 `lb_fill_ready` 时启动，避免启动阶段等待 ping-pong bank 导致 watchdog timeout；
- 25 MHz 与 150 MHz 在 SDC 中按 intentional asynchronous CDC boundary 处理；
- cached adapter 写入口采用 one-entry registered request slice，切断 `pattern_writer -> payload compare -> backend` 的 150 MHz 长组合反馈路径。

## Golden boundary

P1-05A 未破坏 P1-04C 已真板验证的：

- HDMI_B pin；
- 50→25/125 MHz PLL；
- APUG092 protected transmitter；
- EG HDMI PHY；
- PLL lock 后约 20 ms reset hold；
- EDID single trigger；
- `IIC_SCL_DIV=250`；
- 640×480 / 800×525 / VIC=1 timing。

`src/top/p1_hx4s20c_hdmi_board_top.v` 继续作为 HDMI 无信号时的第一 rollback top。

## 下一阶段

下一阶段为 **P1-05B：TF/FAT32/BMP → SDRAM framebuffer → HDMI**。P1-05A 的显示、SDRAM provider、CDC 和 timing-closure 结构视为冻结基线；P1-05B 优先替换固定 pattern writer，不重新改 HDMI golden boundary。

## 文档规则

主要当前文档：

- `README.md`
- `STRUCTURE.md`
- `docs/01_architecture.md`
- `docs/02_implementation_goals.md`
- `docs/03_plan_and_status.md`（唯一状态权威）
- `docs/04_use_cases.md`

开发过程、阶段复盘和候选变更记录统一放 `docs/develop_records/`；`docs/` 根目录不再新增其他当前设计文档。`docs/olds/` 只读保留。
