# B 线计划：板间图片链路、缓冲与主板 1080P 输出

> 负责人：杨文轩。B 线负责两块板之间的图片数据可靠传输、主板缓存/安全提交和 HDMI 视频时序。最终链路是“一次加载一张 1920×1080 图片”，不是持续视频链路；不再安排 YUV422 视频 PHY、视频帧率或 `.vseq` 任务。

## 当前位置

`M2` 的 14 线低速图片链已经真板通过，主板能够显示从板图片并完成切换/轮播。该链路先作为 640×480 回退基线。下一步是 `M3-B`：在不破坏回退基线的前提下，验证 1920×1080 静态图片的传输量、缓冲容量、写入时间和 frame-boundary 提交。

## 1. B 线责任边界

```text
B-S 从板：A payload -> packetizer/CRC -> GPIO TX
B-M 主板：GPIO RX -> 校验/CDC -> SDRAM/line buffer -> safe commit -> HDMI_B/APUG092
```

B 线提供：

- 数据包的 `transaction_id/image_id/sequence/address/length/CRC`；
- valid/ready 或 credit 背压、超时、重试和错误隔离；
- 主板写入 back buffer 或等价的受保护区域；
- `write_fence / frame_ready / frame_boundary / frame_id`；
- `underflow / protocol_error / link_ready`；
- 1920×1080 HDMI raster、像素时钟、APUG092 视频输入边界和最终视频输出。

B 线不负责：

- TF/FAT32/BMP 解析和目录语义；
- 转轮、UI、字幕、转场策略、亮度/对比度策略；
- HDMI 音频样本内容和音频可视化算法（C 线提供样本，B/集成负责送入官方音频端口）。

## 2. 当前 14 线基线与 M3 决策

当前 14 线链路包含 7-bit 分片 mailbox、REQ/ACK、发布反馈、UART 控制和地线。它已经足以证明 640×480 图片事务，但不应直接声称具备 1080P60 视频带宽。由于目标改为静态图片，M3 的指标改为：

```text
一张 1920×1080 图片完整传输
-> 无丢包/错序/半帧提交
-> 加载时间可测、可接受、可恢复
-> 主板在 frame boundary 一次发布
```

M3-0 必须由 A/B/集成在真实资源和杜邦线数量约束下冻结以下选项：

1. 沿用 14 线 mailbox，增加 burst/分包和超时恢复；或
2. 在现有 GPIO 上改成更宽的 source-synchronous 静态图片包；或
3. 采用 RGB565/其他已验证的静态图片传输格式，主板展开到 HDMI RGB888。

在完成带宽、管脚、STA 和真板测量前，不把 74.25 MHz、148.5 MHz 或任何“视频吞吐”数字当作项目承诺。USB 下载口仍不作为板间 FPGA 通信接口。

## 3. 图片事务与安全提交

```text
OPEN(image_id)
  -> allocate back target / clear transaction state
  -> receive BEGIN + packets
  -> verify CRC/sequence/address/count
  -> write fence
  -> wait for a safe frame boundary
  -> publish target image_id
```

约束：

- 当前 front 图片在新图完整通过前保持显示；
- CRC、序列、地址范围、像素计数或 fence 失败时丢弃 back，不污染 front；
- `DONE` 只在主板真正发布目标图片后产生，UART `ACCEPTED` 不算完成；
- `frame_boundary` 内快照宽高、格式、base 地址和图像参数；active line 不切换；
- 复位或断链后清空事务状态，不能把旧包接到新图上。

## 4. 节点任务

| 节点 | B 线任务 | 完成条件 |
|---|---|---|
| `M0` | 保留 P1-05A SDRAM/line buffer/HDMI_B rollback | 旧基线仍能独立综合、上板 |
| `M1` | 冻结 packet、CRC、CDC、GPIO/UART 控制面 | 双板控制面和工程结构通过 |
| `M2` | 14 线图片 mailbox、接收写入、发布反馈、640×480 安全提交 | 从板图片到主板 HDMI `[B]`，当前已通过 |
| `M3` 下一节点 | 1920×1080 静态图片 buffer/packet；容量和加载时间实测；主板 1080P raster 与安全提交 | 至少 4 张 1080P 图片完整显示；0 半帧、0 错序；TD/真板证据建立 |
| `M4` | 为转场保留当前/目标图的 line/tile 或双区域读出；加载时上一帧保持并叠加 loading 状态 | 切换期间不闪屏、不提交半帧 |
| `M5` | 提供稳定的 frame tick、image commit、underflow 和 HDMI audio 输入时序 | 音画边界可被 C 线对齐，异常进入 fallback |
| `M6` | 完成资源、STA、BitGen、复位/断链/长稳验证 | 两份最终 bitstream 可重复构建并通过真板演示 |

## 5. 文件所有权

B 线可修改：

```text
src/dual_board/**
src/framebuf/async_fifo.v
src/framebuf/frame_buffer_manager.v
src/framebuf/p1_sdram_*.v
src/framebuf/sdram_*.v
src/framebuf/line_*.v
src/display/hdmi_1080p_raster.v
sim_tb/dual_board/**  sim_tb/framebuf/**  sim_tb/display/**
```

B 线不得直接修改：

```text
src/storage/**  src/app/**  src/interact/**  src/audio/**
src/top/**  constraints/**  两个长期 .al 工程
```

APUG092 顶层 wrapper、时钟/复位和约束由集成负责人维护；B 提供稳定的视频和音频输入契约。涉及公共接口时，先提交契约和影响范围，不在 A/C 文件中追加隐式端口。

## 6. B→C 接口

```text
pix_clk / pix_rst_n
rgb_valid / rgb_data[23:0]
frame_start / line_start / line_last / frame_boundary
image_id / image_commit
link_ready / underflow_sticky / protocol_error
audio_sample_tick / audio_ready / hdmi_audio_port
```

C 线可以先用固定图片和 mock raster 开发 UI；真实集成必须等待 B 的 `image_commit` 和 `frame_boundary`。C 不得反向驱动 B 的 SDRAM 地址或 swap。

## 7. B 线验收门槛

1. `P1-05A` 仍可随时回退；任何影响 HDMI/SDRAM 的修改都重新做 Questa、TD synthesis、P&R、STA、BitGen。
2. 1080P 静态图按实际像素格式完成容量和加载时间记录；不能以 640×480 或短 PRBS 代替。
3. 错包、重复包、丢包、背压、最后一包、断链和单板复位均不会提交半帧。
4. 主板 1920×1080 raster、HDMI 视频和音频时钟边界独立取得 `[C]`、`[S]`、`[B]` 证据。
5. B 只交付显示事实和链路健康状态，不把 A 的文件状态或 C 的 UI 状态复制到自己的内部状态机。
