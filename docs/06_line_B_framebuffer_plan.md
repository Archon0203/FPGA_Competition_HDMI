# B 线计划：板间链路、缓冲与主板显示输出

> 本文件只描述 B 线任务。全项目使用统一节点 `M0～M6`，每个节点同时列出 A/B/C 任务并在节点末尾汇合。双板 + 1080P 是从 `M1` 开始的主线；720p 只作为链路 bring-up profile，P1-05A 只作为不可破坏的 rollback baseline。

## 1. 责任边界与当前状态

B 线由杨文轩负责，分为两个部署域，但仍是一条 B 线：

```text
B-S（从板）: S SDRAM -> packetizer -> source-synchronous TX
B-M（主板）: RX/CDC/CRC -> line/tile buffer -> scanout -> HDMI
```

B-S 不拥有主板 front/back，也不读取 TF；B-M 不解析 FAT，也不建立第二个 writer。B 线负责 packet 接收、credit、CDC、主板行/tile 缓冲、动态读出、安全提交和 HDMI 1080p 时序。

已完成并冻结的基线：P1-05A cached provider chain `[C-sub] PASS(260)`、官方 APUG011 子链 `[C-sub] PASS(24)`、TD6.2.1 routed `[S]` 和真板 `[B]`。该基线的 640×480 raster、HDMI PHY/PLL、CDC、prefetch 和 cadence 必须可随时回退。

## 2. 文件所有权

B 线可修改：

```text
src/framebuf/async_fifo.v
src/framebuf/frame_buffer_manager.v
src/framebuf/p1_sdram_*.v
src/framebuf/sdram_*.v
src/framebuf/line_*.v
src/framebuf/p1_framebuffer_pattern_writer.v
sim_tb/framebuf/**
sim_tb/integration/tb_p1_sdram_*.v
sim_tb/integration/run_p1_sdram_*.do
src/display/hdmi_1080p_raster.v（新增的、与 vendor PHY 解耦的 profile）
sim_tb/display/tb_hdmi_1080p_raster.v
```

B 线不得修改：

```text
src/storage/**  src/framebuf/p1_media_framebuffer_loader.v
src/framebuf/framebuffer_writer.v（A loader 内部唯一 writer）
src/display/hdmi_*（仅可新增上述独立 raster profile；不得改 P1-04C/P1-05A golden boundary）
src/audio/**  src/interact/**  src/app/**
src/top/**  constraints/**  FPGA_Competition_HDMI.al
```

主板 top、约束和 TD 工程由集成负责人统一维护；B 只提交可独立仿真的 wrapper、链路和 buffer 模块。

## 3. 不可变公共接口

### 3.1 A/B 写入与安全提交

640×480 初始闭环可使用：

```text
A packet/local source -> mem_wr_valid/ready
                       -> B SDRAM write sink
                       -> frame_buffer_manager
```

`frame_buffer_manager` 是唯一 front/back owner；A loader 内部的 `framebuffer_writer` 是唯一 writer owner。B 不例化第二个 writer，也不把历史 `writer_start` 连接成第二条启动路径。完成桥必须满足：

```text
一次 media_cmd -> 一次 load/start
多笔 write     -> write fence
一次 fence     -> 一次 writer_done/writer_ok
swap           -> 只在 display_frame_boundary
```

失败写入、CRC 错误、underflow、短帧或 credit 耗尽都不能污染当前 front。read base、width、height、stride 一帧内保持稳定。

### 3.2 板间数据面

首选 source-synchronous GPIO：

```text
DATA[31:0] + LINK_CLK + VALID/SOF/EOL/EOF + sequence + CRC
```

RX 路径为：

```text
GPIO RX -> deskew/CDC -> CRC/sequence -> RX FIFO
        -> line/tile buffer -> RGB/YUV conversion -> canonical raster
```

控制面由 SPI 完成，数据面不用 SPI 传原始像素。首版目标可从 74.25 MHz link clock + 32-bit packed payload + YUV422 开始，但必须经过 PRBS、CRC、持续吞吐、P&R 和真板门禁，不把候选数值当作已验证时序。

### 3.3 对 C 线的输出

B 向集成层提供 raw stream：

```text
pix_clk / pix_rst_n
fb_pixel_valid / fb_pixel_data[23:0]
frame_boundary / underflow_sticky / protocol_error
```

B 不自行生成第二套 `frame_start/line_start/line_last`。集成层使用唯一的 canonical raster 计数器产生 C 线 sideband；C 不反向驱动 B 的 swap。

### B 对 C 的真实依赖边界

C 的缩放、OSD、转场和音视频同步必须以 B 的输出时序为准，不能以 A 的文件读取节拍为准。B 必须提供：

```text
canonical raster: in_valid / in_data / frame_start / line_start / line_last
commit: frame_boundary
health: underflow_sticky / protocol_error / link_ready / frame_id
```

C 可以在 M1 用 deterministic raster 或 PRBS mock 编写处理链；M2 的 pass-through 只能算子链验证。M3 起，C 的缩放和状态页要接入真实 B raw stream；M4 的 1080P UI/OSD 只有在 B 的 1080P timing profile、line/tile buffer 和 frame-boundary commit 通过后才算集成完成。B 不等待 C 的 UI 实现，始终先输出可旁路的 canonical raster。

## 4. 统一节点中的 B 线任务

| 统一节点 | B 线任务 | B 线完成证据 |
|---|---|---|
| `M0` | 回归 P1-05A cached adapter、CDC、prefetch、line buffer、HDMI cadence；固定 pattern 可回退 | 既有 `[C-sub]/[S]/[B]` 证据保持通过 |
| `M1`（当前） | 冻结 SPI/GPIO 引脚候选、packet RX/TX 接口、CRC/sequence、credit、CDC 和 frame-boundary commit；尽早核对 1080p pixel/serial clock、PLL/PHY 能力、GPIO pin/IO 时序和有效吞吐预算；建立 PRBS/loopback harness；先向 C 提供 canonical raster/health mock | PRBS/CRC/CDC TB；1080p feasibility 与 pin/timing budget 有记录；最大暂停和异步 reset 不丢包；C 可用 mock 验证 sideband 消费 |
| `M2` | 完成 640×480 双板第一闭环：B-S packet TX、B-M RX/FIFO/line buffer、write sink、front/back 和动态 read wrapper；向 C 暴露真实 frame_boundary/underflow/protocol_error | mock/真实 A packet 可写入 back；一次 start/done；失败不污染 front；C pass-through 能观察真实状态 |
| `M3` | 完成双板链路 720p bring-up：持续吞吐、credit、line/tile buffer、YUV/RGB 转换、underflow/fallback | 720p packet 持续传输，CRC/sequence/underflow 门禁通过 |
| `M4` | 完成主板 1920×1080 HDMI profile、148.5 MHz pixel/742.5 MHz serial 预算、1080p line/tile scanout | 1080p 静态图 RTL、P&R、STA 和真板证据 |
| `M5` | 接入视频帧调度、动态源切换、丢包/欠载恢复、frame-boundary commit；保持 P1-05A fallback | 视频切换无半帧，异常恢复可观察 |
| `M6` | 完成最终 top、资源/STA/BitGen、双板真板长稳和回退镜像 | 图片、视频、转场、音频演示的 `[C]/[S]/[B]` 证据 |

## 5. 时钟域与数据完整性

| 通路 | 要求 |
|---|---|
| S physical/link → S/M logic | source-synchronous 接收、deskew、FIFO 或握手 CDC；不可组合跨域 |
| A loader → SDRAM write | valid/ready 或 async FIFO；payload 在未接受时稳定 |
| A completion → manager | toggle/握手，只消费一次 |
| manager → pixel/read | frame-boundary 双寄存器快照 |
| pixel boundary → manager | 单拍事件 toggle/握手，不直接采样脉冲 |

测试必须注入 backpressure、链路暂停、异步 reset、CRC 错误、重复/丢包和最后一笔写。不能用 false path 隐藏 150 MHz 同域逻辑；每次 active top 或约束修改都重新综合、P&R、STA 和 BitGen。

## 6. 分辨率策略

```text
M2：640×480 双板架构闭环（第一媒体规格）
M3：1280×720 链路 bring-up（仅门禁/调试 profile）
M4～M6：1920×1080 主板 HDMI + 双板持续媒体（最终目标）
```

1080p 单帧约 2,073,600 个 32-bit word，不能沿用 640×480 单板 A/B 全帧双缓冲。主线采用从板缓存下一帧、主板 line/tile buffer 和 frame-boundary 提交；主板是唯一 HDMI 输出 owner。

## 7. B 线验收门槛

1. P1-05A rollback 始终可编译、可综合、可生成 bitstream。
2. packet 错误只能保留上一帧、显示 fallback 或进入应急画面，不能提交半帧。
3. 一帧内 read base/geometry 稳定，swap 只发生在 frame boundary。
4. 1080p profile 独立取得 `[C]`、`[S]`、`[B]`；720p 通过不能代替 1080p 验收。
5. B 线只交付 raw stream 和链路状态，不侵入 C 的 UI 状态机，也不要求 A 访问主板内部地址。
