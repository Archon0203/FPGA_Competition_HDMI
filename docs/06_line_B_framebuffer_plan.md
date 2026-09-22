# B 线计划：双缓冲、SDRAM 与显示读出

## 1. 依据、目标与当前状态

B 线负责把 A 线的单一媒体写事务安全地落入 internal SDRAM，并从稳定的 front framebuffer 连续读出 RGB，交给集成层和 C 线。P1-05A 已完成并冻结的路径是 B 线的 golden baseline：

```text
framebuffer pattern
 -> cached adapter/APUG011
 -> 25↔150 MHz CDC
 -> prefetch/ping-pong line buffer
 -> P1-04C HDMI_B
```

已有证据包括 P1-05A cached provider chain `[C-sub] PASS(260)`、官方 APUG011 子链 `[C-sub] PASS(24)`、TD6.2.1 routed `[S]`（setup/hold 违例为 0）。但硬件最小 hold 裕量约 `+0.003 ns`，后续任意 active-netlist 改动都必须重新完整 STA；TD6.2.1 bitstream 仍需重新上板复测。B 线的首要原则是保护这条 640×480 显示基线。

## 2. 架构决策与文件所有权

B 线拥有：

```text
frame_buffer_manager
SDRAM write sink / arbiter 接口
front/back metadata、pending_swap、swap
SDRAM read、CDC、prefetch、line buffer、raw scanout
```

B 线不得再例化或控制 `framebuffer_writer`。该 writer 已由 A 线 `p1_media_framebuffer_loader` 内部持有，唯一链路为：

```text
A loader.mem_wr_*
  -> B SDRAM write sink
  -> sdram_arbiter
  -> p1_sdram_cached_adapter
  -> APUG011/internal SDRAM
```

B 线可以修改：

```text
src/framebuf/*.v（p1_media_framebuffer_loader.v 除外）
sim_tb/framebuf/**
sim_tb/integration/tb_p1_sdram_*.v
sim_tb/integration/run_p1_sdram_*.do
```

B 线不得修改：

```text
src/storage/**  src/framebuf/p1_media_framebuffer_loader.v
src/display/hdmi_*.v  src/audio/**  src/interact/**  src/app/**
src/top/**  constraints/**  FPGA_Competition_HDMI.al
```

## 3. B 线接口契约

### 3.1 写入与完成桥

写入 sink 对 A 暴露：

```text
mem_wr_valid / mem_wr_ready
mem_wr_addr[20:0]
mem_wr_data[31:0] = 0x00RRGGBB
```

manager 对集成层暴露：

```text
load_ready
load_busy
write_base / write_geometry
writer_done / writer_ok / writer_error
```

`writer_done/writer_ok` 是 manager 的消费语义，不是第二个 writer 的控制源。集成层只把 A loader 的 `load_done/load_ok/load_error` 桥接到这组信号；manager 不得直接启动 A loader 内部 writer。

当前 `frame_buffer_manager` RTL 中仍存在 `writer_start` 输出，这是历史的外部-writer 控制接口。在 P1-05B 集成中它必须保持未连接或由 integration wrapper 明确转译为 A loader 的 `start`，绝不能再连接到第二个 `framebuffer_writer`；该遗留端口的处理必须在 I2.5 gate 中通过单次 start/done 断言确认。

### 3.2 双缓冲与安全换帧

manager 是唯一 front/back owner。规则如下：

1. `load_ready=1` 时才为 A 分配 `write_base`；一帧写入期间 base、尺寸和 stride 固定；
2. A 完整写入且 `writer_ok=1` 后，manager 将 back metadata 标成 `pending_swap`；
3. provider fault、协议错误、短帧或 underflow 不得污染当前 front；
4. `swap_pulse` 只能在 `display_frame_boundary` 发生；active line 内不得改读基址；
5. swap 后，旧 front 才能重新成为可写 back，避免正在读的帧被覆盖。

### 3.3 动态读出约束

当前 `p1_sdram_hdmi_pipeline` 的 `FRAME_BASE=0` 是固定参数，不能直接当作 P1-05B 的 A/B 读出实现。B 线必须提供 manager-aware dynamic read wrapper/parameter path，把提交后的 `read_base/read_geometry` 接入既有读出链。一帧内 read base、width、height、stride 必须稳定；新 metadata 在 frame boundary commit 后才可生效。

### 3.4 对 C 的 raw 输出

B 线输出的是 raw framebuffer stream，不自行伪造 C 线的 raster sideband：

```text
pix_clk / pix_rst_n
fb_pixel_valid
fb_pixel_data[23:0]
frame_boundary
underflow_sticky
protocol_error
```

P1-04C/APUG092 的 `axis_user/axis_valid/axis_last` cadence 仍由冻结的官方 timing source 产生。集成层根据 P1-04C golden raster 生成 C 线所需的 canonical `frame_start/line_start/line_last`，避免 B 和 C 各自定义一套行帧边界。

## 4. 时钟域契约

| 通路 | 来源 → 目的 | 要求 |
|---|---|---|
| 写数据 | A loader/provider → SDRAM write domain | async FIFO 或 valid/ready CDC；不靠组合跨域 |
| 写完成 | A `load_done/ok` → manager control | toggle/握手同步；完成只消费一次 |
| frame status | manager/control → pixel domain | synchronizer 或 event FIFO |
| 显示边界 | pixel/raster → manager/control | 单拍事件 toggle/握手，不能直接采样脉冲 |
| 读 metadata | manager → pixel/read domain | frame-boundary 双寄存器快照 |
| raw stream | SDRAM read → pixel | 复用已验证 CDC、prefetch、line buffer |

所有 CDC 都必须在 harness 中注入暂停、异步 reset 和边界事件，且不能通过 false path 隐藏 150 MHz 同域逻辑。

## 5. B 线分阶段计划

### B0：P1-05A baseline 回归

回归 cached adapter、CDC bridge、prefetch、ping-pong line buffer、scanout、官方 APUG011 compatibility 和固定 pattern。任何失败先回退 P1-05A，不在同一 PR 内做 HDMI low-level 重构。

### B1：双缓冲 metadata

用纯 RTL harness 验证 base、尺寸、stride、valid、pending_swap 和 frame-boundary swap。证明失败写入不会污染 front，pending 帧不会在提交前显示或被覆盖。

### B2：write sink 与 mock A

用 mock media source 驱动 `mem_wr_*`，验证 full-frame write、backpressure、最后一笔、provider completion 和错误注入。明确一次 load 只对应一次 manager completion。

### B3：manager-aware read

把 back-buffer metadata 接入动态读 wrapper，继续复用现有 `p1_sdram_read_cdc_bridge`、line prefetch 和 ping-pong buffer。验证一帧内地址稳定、`underflow=0`、active line 连续。

### B4：真实 A/B 子链

接入 A loader 的真实 `mem_wr_*` 和 completion bridge，C 端仍使用固定 pattern/bypass。检查非法文件、写失败、重复 start/done 和安全换帧。

### B5：candidate top

只有 A/B 子链通过后，集成负责人才能把 wrapper 接入 active top；保留固定 pattern fallback，并对任何 top 变更重新综合、P&R、STA 和 BitGen。

## 6. B 线验收门槛

1. P1-05A 全部既有回归保持通过；
2. writer start/done 只有一个来源，manager 不重复例化或启动 writer；
3. swap 只发生在 frame boundary，读基址一帧内不变；
4. CDC 经过异步 FIFO/synchronizer 验证，不能以约束掩盖真实路径；
5. 写失败、读 underflow、provider fault 可观测且不会显示半帧；
6. active top 变更具备 TD6.2.1 final STA、资源报告和 rollback evidence。
