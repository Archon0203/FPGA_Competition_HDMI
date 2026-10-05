# 01 · 系统架构（P0 → P4）

> 本文只定义系统架构、最终职责边界和长期冻结接口，不维护日常进度。**所有当前 PASS/未通过/待验证状态只以 `docs/03_plan_and_status.md` 为准。** P1-05A 与 P1-04C 继续作为已关闭的 rollback baseline。

## M2 当前部署 profile（2026-10-04）

主板 `m2_master_tf_hdmi_top`：按键/UART coordinator → 14 线接收/CRC → SDRAM/行缓存 → 加载 UI → 官方 HDMI_B。从板 `m2_slave_media_tx_top`：TF/FAT32/BMP → 带地址像素流/CRC → 握手发送与 UART 状态。当前低速图片 profile 允许从板直接流式发送，不要求先在从板存完整帧；正式视频 profile 再加入从板 SDRAM 预取与高速 line/tile transport。两者共用 A/B/C 职责边界，不能把低速验证链当作 1080p60 最终 PHY。

主板发布状态反馈后从板才报告 DONE。无缝转场需后续双缓冲，当前掩蔽单缓冲。最终仍为双板 + 1080p + 团队要求的全部 1.4 扩展。细节及实测资源见 [当前 profile](develop_records/M2_MASTER_OUTPUT_20261004.md)。


## 1. 总体阶段

| 阶段 | 职责 | 架构定位 |
|---|---|---|
| P0 · Media Core | 文件流、BMP、framebuffer、抽象 SDRAM、整行预取、连续 RGB888 | 已关闭基础媒体 RTL |
| P1 · Vendor & Board | APUG011 / APUG092 / PLL / HX4S20C integration | 已关闭 board/vendor rollback baseline |
| P2 · Presentation | HDMI audio、OSD、参数调节、转场、交互、应急 UI | 最终由 Master 合成 |
| P3 · Short Video | `.vseq`、帧调度、色彩转换、缩放 | Slave 生产媒体、Master 显示 |
| P4 · 双板 + 1080p 主线 | 从板媒体生产、双板 packet、主板 1920×1080 输出 | 最终交付架构；状态见 `03` |

原则：已经取得的低层证据不因上层开发自动失效。P1-05B 若出现 HDMI 问题，先回退 P1-05A framebuffer baseline 或 P1-04C HDMI baseline，不重新猜 pin/PLL/vendor PHY。

## 2.1 双板主从部署边界

第二块 HX4S20C 用于扩大媒体缓存和处理规模，不把两块板当作共享内存。主板（M）是唯一的最终显示时序和 HDMI 音视频输出所有者；从板（S）是媒体生产者，负责 TF/FAT32/BMP、视频帧预取和向主板提供帧/行/tile 数据。

```text
S: TF -> media catalog/decoder -> S SDRAM -> source-synchronous link
                                                       |
M: control/coordinator -> link RX -> line/tile buffer -> UI/OSD/effects
                                                       -> APUG092/HDMI
```

主板向从板发送命令、格式、credit 和 heartbeat；从板只返回媒体描述符、数据、状态和 CRC。任何从板协议都不能直接修改主板 `framebuffer_base`、HDMI raster 或 front/back owner，避免板间形成循环依赖。


### 2.1A 为什么最终必须“Slave 生产媒体、Master 输出 1080P”

M1 真板为了观察控制链，临时让 Slave 接 HDMI；该 profile 已验证成功，但最终作品不沿用该职责。最终分工冻结为：

```text
Slave = media producer / cache / packet source
Master = coordinator / final renderer / HDMI owner
```

原因不是简单把两块 FPGA 的 LUT 相加，而是切断两个完全不同的时序与存储压力域：TF/FAT32/BMP/vseq、目录、预取和媒体缓存主要是低速/突发/状态机密集逻辑；1080p raster、缩放、OSD、转场、音频和 APUG092 是持续高吞吐、严格时序逻辑。把前者移到 Slave，可让 Master 的高频 timing cone 保持可控。

1920×1080 一帧为 2,073,600 像素。若继续使用 P0/P1 历史的 32-bit/像素表示，单帧几乎占满 2M×32 SDRAM，无法在一块 EG4S20 内简单维持两张完整 1080p RGB888 framebuffer 再叠加文件系统/OSD 缓冲。因此最终链路采用 **Slave 源缓存 + packed YUV422 line/tile 流 + Master 小规模 FIFO/line/tile buffer + frame-boundary commit**，而不是“先把两张完整 1080p 帧都复制到 Master”。

M1 的 Slave HDMI 工程永久保留为诊断回退：它证明控制平面和 A/B/C 组合可观察。M2 的**完整验收目标**要求真实媒体从 Slave 送到 Master，并逐步把最终 HDMI owner 切回 Master；开发期间 Slave HDMI 可继续承担本地媒体诊断。

控制平面首选主板 SPI master / 从板 SPI slave；数据平面首选 40Pin GPIO 上的 source-synchronous 32-bit packed YUV422 链路，目标时钟先定为 74.25 MHz。该配置只作为候选，必须先通过 PRBS、CRC、CDC、持续带宽和 P&R 门禁；不能把千兆以太网当作原始 1080p60 像素链路。以太网可作为调试、文件搬运或压缩媒体的后备通道。

### 2.2 板间物理接口与通信方案

HX4S20C 原理图提供两组 40-pin DC3 扩展口（GPIOA/GPIOB）。接口本身没有专用 FPGA-to-FPGA USB 或高速收发器，所有板间信号都必须由 GPIO 复用实现。两板必须共地，信号电平按 3.3 V LVCMOS 设计，禁止把任一端的 5 V 引脚作为 FPGA 信号驱动；3.3 V/5 V 只按原理图定义作为供电参考，不能直接给另一板供电。

板载 USB 不作为今天的板间通信方案。USB 下载口用于配置 FPGA；USB-UART 可以把 FPGA 的 TXD/RXD 接到电脑，但两块板的 USB 设备口不能用普通 USB 线直接互连并自动形成 FPGA-to-FPGA 通道，除非额外实现 USB Host/Device 协议和对应物理连接。当前只有杜邦线时，优先使用 GPIOA/GPIOB 上的普通 3.3 V GPIO 做低速 UART 验证。

推荐分层如下：

| 层 | 首选实现 | 用途 | 验证要求 |
|---|---|---|---|
| 控制面 | 4-wire SPI：M SCK/MOSI/CS，S MISO | `READY/OPEN/PAUSE/CREDIT/STATUS/ERROR`、descriptor 摘要、heartbeat | 先用 1-10 MHz；独立 SPI loopback，再做两板握手和 reset 恢复 |
| 数据面候选 A | 32-bit single-ended DATA + LINK_CLK + VALID/SOF/EOL/EOF | packed YUV422 行/tile 数据 | 从 25 MHz PRBS 开始，逐步到 74.25 MHz；必须有 CRC、sequence、credit、CDC 和误码注入 |
| 数据面候选 B | 16-bit DATA + LINK_CLK，按 148.5 MHz 发送 | 当 32-bit GPIO 布线/时序不可收敛时的备选 | 只有候选 A 在管脚、STA 或信号完整性上失败时启用 |
| 后备通道 | 千兆 Ethernet | 调试、文件搬运或压缩媒体 | 不作为首版原始 1080P60 像素链路 |

40-pin 连接器的具体 GPIO 编号、方向、IO 标准、时钟脚和地线分配必须在 M1 形成一张 pin map，并由 B 线和集成负责人共同冻结；在此之前，计划中的 74.25 MHz 和 32-bit 只是候选参数，不能写入正式约束或宣称已具备吞吐能力。

当前工程级候选分配为：GPIOA/J1 承载数据面（DATA、LINK_CLK、VALID、SOF/EOL/EOF、CRC/sequence 辅助信号），GPIOB/J2 承载 SPI 控制面、heartbeat、reset/status 和少量调试信号。该分配只是便于布线和职责隔离的起点；最终必须根据两块板的实际线缆方向、管脚 IO 能力、时钟能力和 P&R/STA 结果确认，不能直接视为已冻结 pinout。

#### M1 今日最小双板验证 profile

在 40-pin 排线和高速链路尚未具备时，先用三根杜邦线验证控制面：

```text
master GPIO_TX  -> slave GPIO_RX
slave  GPIO_TX  -> master GPIO_RX
master GND      -- slave GND
```

两端均使用普通 GPIO 和 3.3 V LVCMOS；不要连接 5 V。协议先采用 8N1、115200 baud、固定短帧，不传原始像素：`0x55 0xA5 opcode length payload crc8`。第一帧只做 `PING/READY`，随后做 `OPEN/STATUS/ABORT`，接收端用 LED 或数码管显示计数/错误码。验证顺序为：分别烧录 `master.bit` 和 `slave.bit` → 不接线单板自检 → 接 GND → 接 TX/RX → master 发送 PING → slave 回 ACK → 注入 reset 后重复握手。该 profile 只证明 GPIO 电气连接、两个角色 bitstream 和最小控制协议，不替代 SPI 或 source-synchronous 媒体链路。

### 2.3 双 bitstream 构建与板级验证

双板使用同一共享 RTL 工程，但生成两个角色不同的 bitstream：

```text
master_top + master ADC/SDC -> master.bit
slave_top  + slave  ADC/SDC -> slave.bit
```

更换 Top 或约束后必须分别执行 synthesis、P&R、STA 和 BitGen；不能复用另一角色的 P&R 结果。输出目录和文件名必须分离，烧录记录必须标明板号、角色、commit 和 bitstream 哈希。

板级验证顺序固定为：

1. 单板验证 `slave.bit`：50 MHz、复位、SPI slave、GPIO TX、状态 LED，不接主板也能显示 READY/错误状态。
2. 单板验证 `master.bit`：50 MHz、SPI master、GPIO RX、P1-05A rollback HDMI 输出，未接从板时仍能显示 fallback。
3. 两板控制面验证：先只接 SPI，完成 `READY -> OPEN -> STATUS -> PAUSE/ABORT` 和异步复位恢复。
4. 两板数据面验证：接入 PRBS/CRC/sequence，先低速再提升链路时钟；记录误码、丢包、重复包和 backpressure。
5. 媒体闭环验证：写入 `slave.bit` 与 `master.bit`，从板真实 TF 媒体经链路到主板安全提交；最后再分别取得双板 `[S]`、`[B]` 和长稳证据。

1080p 主目标使用 1920×1080 / 148.5 MHz pixel / 742.5 MHz serial 的独立 HDMI profile。1280×720 仅保留为可选故障隔离 profile；M3 的正式门禁改为 1080p packed-YUV422 等效吞吐，避免把时间投入到并非最终验收的 720p 路线上。第二块板不能替代最终 HDMI 输出板对 APUG092/PHY 高速时序的验证；1080p 与双板链路均不得改变 P1-05A 640×480 rollback baseline。

## 2. P0 媒体契约

```text
fat32_file_reader
        ↓
bmp_parser / bmp_pixel_stream
        ↓
framebuffer_writer
        ↓
frame_buffer_manager
        ↓
sdram_arbiter
        ↓
[ abstract SDRAM provider ]
        ↓
line_prefetcher
        ↓
line_buffer_pingpong
        ↓
continuous display-order RGB888
```

固定契约：1 pixel = 1×32-bit word，`0x00RRGGBB`；640×480 双缓冲历史基线 A=0、B=307200 words；frame swap 只在显示帧边界；active line 内不允许 pixel-valid gap。

## 3. P1-02B SDRAM backend

P1-02B 已证明 `sdram_arbiter -> sdram_adapter -> official APUG011 -> EG_PHY_SDRAM_2M_32` 在独立 TD harness 中可完成 150 MHz timing closure。P1-05A 不修改其协议语义，而为连续视频新增独立 `p1_sdram_cached_adapter`。

## 4. P1-04C HDMI golden boundary

```text
HX4S20C 50 MHz (R7)
        ↓
p1_hdmi_pll_50m_25_125
        ├─ 25 MHz pixel
        └─ 125 MHz serial
        ↓
~20 ms reset hold + EDID trigger
        ↓
hdmi_official_baseline_source
        ↓
APUG092 transmitter
        ↓
EG HDMI PHY / EG_LOGIC_ODDR
        ↓
HDMI_B
```

冻结参数：free-running raster、`IIC_SCL_DIV=250`、640×480 / 800×525 / VIC=1，以及已经真板验证的 HDMI_B pin。P1-05A 没有改变这些边界。

## 5. P1-05A 最终架构

### 5.1 写入路径

```text
p1_framebuffer_pattern_writer @150 MHz
          ↓
     sdram_arbiter
          ↓
p1_sdram_cached_adapter
          ↓
official APUG011
          ↓
internal SDRAM
```

固定图案：8 px 白边；左上红、右上绿、左下蓝、右下黄；中央 16 px 洋红竖条和 16 px 青色横条。

`p1_sdram_cached_adapter` 的写入口采用 one-entry registered request slice：上游 valid/ready 握手时锁存 address/data，后续 APUG011 masked 4-word transaction 只依赖内部寄存器，避免 writer payload 组合回馈形成 150 MHz 长路径。

### 5.2 连续读带宽

P1-02 random-word adapter 每个 abstract read 都会扩展为一个完整 4-word APUG011 group。连续 framebuffer 读会重复访问同一组，因此 P1-05A 使用 4-word read cache：

```text
first lane miss -> read one aligned 4-word APUG group -> cache all lanes
next 3 lanes    -> cache hit -> no repeated provider group
```

该修复消除了真板上“正确彩色窄线向下移动、其他行黑”的持续 line-underflow 现象。

### 5.3 CDC 与行预取

```text
150 MHz SDRAM side
      ↕ async FIFO / synchronizer
25 MHz pixel side
      ↓
line_prefetcher
      ↓
line_buffer_pingpong
      ↓
hdmi_framebuffer_scanout
```

request 为 25→150 MHz，response 为 150→25 MHz；只允许通过显式 CDC 结构跨域。SDC 将 25 MHz pixel 与 150 MHz SDRAM 时钟组声明为 asynchronous，避免把合法 async-FIFO crossing 当作单周期同步路径，同时保留两个时钟域内部的真实 STA。

prefetch scheduler 只有在 `lb_fill_ready=1` 时才允许开始新行事务。启动阶段 line0/line1 占满两个 ping-pong bank 是正常 backpressure，不再误触发 watchdog timeout。

### 5.4 HDMI 安全切换

APUG092 的 `axis_user/axis_valid/axis_last` 始终由 P1-04C free-running source 产生。P1-05A 只提供 `axis_data`：

```text
P1-04C bars
   ↓
SDRAM init + full-frame write
   ↓
line warm-up
   ↓
safe frame boundary
   ↓
axis_data -> SDRAM framebuffer RGB
```

这使存储链失败仍可观察 HDMI fallback，而不会破坏 link cadence。

## 6. P1-05A timing boundary

TD5.6.2 combined implementation（历史 closeout）：

```text
Setup errors  0
Hold errors   0
Setup WNS    +0.068 ns
Hold WHS     +0.131 ns
TNS           0
```

150 MHz domain：Min Period `6.598 ns`，Max Freq `151.561 MHz`。因此 P1-05A 已达到 `[S]`，但 68 ps 的整体 setup margin 很薄。**后续 P1-05B 每次影响 active design 的修改都必须重新 P&R + STA；不得把本次 closure 当作可继承裕量。**

### 6.1 P1-05A TD6.2.1 routed result

报告 `FPGA_Competition_HDMI_Runs/phy_1/final_timing.rpt` 于 2026-09-21 11:40:27 生成，Top 为 `p1_hx4s20c_sdram_hdmi_top`，工具为 TD 6.2.168116。该报告为 routed/final STA，coverage `99.17%`，所有报告端点均无 setup/hold violation：

```text
SWNS (setup)  +0.599 ns
STNS           0.000 ns
HWNS (hold)   +0.003 ns
HTNS           0.000 ns
violating endpoints  0 / 0
```

相关时钟域的报告值为：25 MHz `SWNS=+9.489 ns/HWNS=+0.003 ns`，150 MHz `+0.752/+0.067 ns`，50 MHz `+10.216/+0.648 ns`，125 MHz `+0.599/+0.285 ns`。这里的 `HWNS=+0.003 ns` 是当前最小硬件 hold 裕量，不能表述为“时序裕量充足”。

此前 TD6.2.1 预优化报告中的 overall `SWNS=-7.098 ns`、150 MHz `SWNS=-1.119 ns` 是历史问题记录，不再代表当前 routed result。当前约束使用 `derive_clocks`；未使用 false path 掩盖 150 MHz 同域逻辑。两条 APUG011 相位相关硬宏边界例外仍按约束文件限制在 clkc[2]↔clkc[1] 方向。

本轮 source-level 优化只做两项低风险修改：

1. `p1_sdram_cached_adapter` 增加 `ENABLE_RUNTIME_DIAGNOSTICS` 参数。仿真默认 `1`，保留原有计数器/冗余协议断言；P1-05A board top 设置为 `0`，使这些非数据通路逻辑不进入生产 150 MHz timing cone。provider response legality check 仍保留。
2. `p1_hx4s20c_sdram_hdmi_top` 的 HDMI reset **释放**使用 50 MHz 上升沿，与官方板级例程一致。曾尝试下降沿来避开 25 MHz pixel rising-edge removal 临界点，但 TD6.2.1 报告显示它缩短了 125 MHz serial-domain recovery window，因此已恢复上升沿实现。

上述 source-level 修改已在当前 TD6.2.1 routed run 中得到实现和时序结果，BitGen 也已生成 `FPGA_Competition_HDMI_Runs/phy_1/FPGA_Competition_HDMI.bit`；该 bitstream 已重新上板显示正常，因此当前工具链取得 `[B]`。

当前 run 仍记录以下 critical warning，需在后续约束/实现复盘中单独处理：

- `u_internal_sdram` 两个初始 location 未被接受，ECO placement 已移动实例；
- 1 条时钟网使用 local routing resource，目标为 `u_sdram_pll/pll_inst.clkc[2] -> SDRAM_CLK`。

## 7. P1-05A baseline 资源边界

P1-05A 已关闭实现的 post-route area report：LUT `7416/19600 = 37.84%`、REG `2554/19600 = 13.03%`、BRAM9K `10/64 = 15.62%`、BRAM32K `0/16`、DSP `1/29 = 3.45%`、PLL `2/4 = 50%`、GCLK `2/16 = 12.5%`。

TD5.6.2 historical closeout 的 LUT/REG `9977/2825` 不用于描述当前 TD6.2.1 routed netlist。

该数字只描述 P1-05A rollback netlist，**不得用来描述当前 M2 Slave 资源占用**。M2 当前资源状态统一见 `docs/03_plan_and_status.md`。

## 8. P1-05A 冻结边界

P1-05A closeout 后默认冻结：

1. HDMI_B pin 与 ADC；
2. HDMI 50→25/125 MHz PLL；
3. APUG092 protected source / EG PHY；
4. reset / EDID / IIC divider；
5. 640×480 raster；
6. 25↔150 MHz CDC 结构与 asynchronous clock-group 约束；
7. cached-adapter sequential read cache 与 registered write request boundary；
8. prefetch bank-availability scheduling invariant。

## 9. 双板 + 1080p 主线中的 P1-05B

P1-05A 是持续保留的 rollback baseline。P1-05B 的 TF/FAT32/BMP 图片能力是双板主线的第一种媒体规格。开发过程中允许使用 Slave 本地 HDMI 做真实 TF/BMP 诊断门禁，但该本地门禁**不改变**最终双板职责，也不能代替 Master-owned M2 完整闭环：

```text
从板 TF -> FAT32/BMP -> media service -> 板间 packet
                                  -> 主板 buffer/安全提交 -> HDMI
```

P1-05A HDMI golden boundary 继续保护；但双板接口、主板 1080p profile 和媒体格式从开发开始就按最终架构设计，避免先做单板接口再二次改造。

## 10. 统一开发节点与分辨率策略

```text
M0  P0/P1-05A 已有基线
M1  双板协议、1080p 架构/时钟/引脚契约与开发骨架
M2  双板 640×480 TF/BMP 第一闭环（P1-05B 功能并入此节点）
M3  1080p packed-YUV422 等效数据链吞吐门禁（720p 可选排错）
M4  双板媒体 + 主板 1920×1080 静态图和 UI
M5  视频、切换、转场、音频
M6  1.4 扩展及双板 1080p 最终交付
```

三人始终分别负责 A/B/C 一条开发线，集成负责人在每个 `M` 节点收口；不另设 I/Q 两套阶段或阶段性重复分工。1280×720 只作为排错时可选 profile，不是必经节点；M3 直接用 1080p 等效 payload 做数据链压力。P2/选题 1.4 的图层/字幕、转场、自适应缩放、实时参数/OSD 和音频可视化纳入 M4～M6；主板完成 UI 合成，从板提供媒体流。若链路不能承载两路源，允许从板预混合，但主板 1080p 输出仍是必需验收。
