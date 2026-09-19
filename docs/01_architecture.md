# 01 · 系统架构（P0 → P4）

> 本文是当前架构权威。当前板级稳定基线已经从 P1-04C HDMI 八色条推进到 **P1-05A internal SDRAM framebuffer → HDMI_B `[S][B] PASS / CLOSED`**；P1-04C 继续作为 HDMI rollback baseline。

## 1. 总体阶段

| 阶段 | 职责 | 当前证据 |
|---|---|---|
| P0 · Media Core | 文件流、BMP、framebuffer、抽象 SDRAM、整行预取、连续 RGB888 | `[C]` |
| P1 · Vendor & Board | APUG011 / APUG092 / PLL / HX4S20C integration | P1-02B `[S]`；P1-04C `[B]`；P1-05A `[S][B] CLOSED` |
| P2 · Presentation | HDMI audio、OSD、参数调节、转场、交互、应急 UI | 待整合 |
| P3 · Short Video | `.vseq`、帧调度、色彩转换、缩放 | 待整合 |
| P4 · Stretch | 720p 优化、1080p/双板、SDIO | feasibility |

原则：已经取得的低层证据不因上层开发自动失效。P1-05B 若出现 HDMI 问题，先回退 P1-05A framebuffer baseline 或 P1-04C HDMI baseline，不重新猜 pin/PLL/vendor PHY。

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

## 6. P1-05A final timing boundary

TD5.6.2 combined implementation：

```text
Setup errors  0
Hold errors   0
Setup WNS    +0.068 ns
Hold WHS     +0.131 ns
TNS           0
```

150 MHz domain：Min Period `6.598 ns`，Max Freq `151.561 MHz`。因此 P1-05A 已达到 `[S]`，但 68 ps 的整体 setup margin 很薄。**后续 P1-05B 每次影响 active design 的修改都必须重新 P&R + STA；不得把本次 closure 当作可继承裕量。**

### 6.1 TD6.2.1 migration timing candidate

官方要求将工具链切换到 TD6.2.1 后，旧 source baseline 的 routed report 出现工具模型与硬件路径裕量分离：overall `SWNS=-7.098 ns`、`HWNS=+0.011 ns`；150 MHz self-domain 为 `SWNS=-1.119 ns`、`HWNS=+0.182 ns`。当前不把 SWNS 负值通过 false-path/clock-group 掩盖；150 MHz same-domain path 仍按真实 synchronous path 分析。

本轮 source-level 优化只做两项低风险修改：

1. `p1_sdram_cached_adapter` 增加 `ENABLE_RUNTIME_DIAGNOSTICS` 参数。仿真默认 `1`，保留原有计数器/冗余协议断言；P1-05A board top 设置为 `0`，使这些非数据通路逻辑不进入生产 150 MHz timing cone。provider response legality check 仍保留。
2. `p1_hx4s20c_sdram_hdmi_top` 的 HDMI reset **释放**使用 50 MHz 上升沿，与官方板级例程一致。曾尝试下降沿来避开 25 MHz pixel rising-edge removal 临界点，但 TD6.2.1 报告显示它缩短了 125 MHz serial-domain recovery window，因此已恢复上升沿实现。

上述两项修改尚未取得新的 TD6.2.1 P&R、BitGen 或真板证据，因此状态仍为 candidate，不覆盖 P1-05A 历史 closeout。

## 7. 资源边界

Post-Phy：LUT 9977/19600、REG 2825/19600、BRAM9K 10/64、BRAM32K 0/16、PLL 2/4。

资源尚可继续推进，但 LUT 已使用约 50.9%。此前 `ram_style` 尝试没有显著增加 BRAM 使用，line-buffer ERAM 化作为后续资源优化项保留；不要在 P1-05A closeout 后立即重构已稳定路径，除非 P1-05B 资源/时序确实要求。

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

## 9. 下一阶段 P1-05B

P1-05B 只在此稳定 framebuffer baseline 上替换固定写源：

```text
TF -> FAT32 -> BMP -> framebuffer_writer -> SDRAM -> existing P1-05A display path
```

随后恢复 A/B framebuffer 与 frame-boundary swap。TF、FAT32、BMP 不与 HDMI low-level bring-up 混在一起。
