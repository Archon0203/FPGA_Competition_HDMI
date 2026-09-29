# C 线计划：主板 UI、交互、转场与音频

> 本文件只描述 C 线任务。全项目使用统一节点 `M0～M6`；A/B/C 在同一节点并行，节点汇合后再前进。C 线从 `M1` 就按主板 M + 双板 + 1920×1080 的接口设计，640×480/720p 只用于验证和回退。

## 1. 责任边界与当前状态

C 线由张宗负责，部署在主板 M，负责：

```text
按键/拨码 -> media_cmd -> coordinator/SPI command
canonical raster -> enhance -> scale -> transition -> OSD/UI -> HDMI data
PCM/tone -> audio stream -> integration/APUG092 audio boundary
```

C 不读取从板 TF，不直接驱动 GPIO packet 时钟、A writer、主板 framebuffer base 或 SDRAM。主板 HDMI PHY、PLL、reset、EDID、官方 `axis_user/valid/last` cadence 由集成负责人维护为 golden boundary。

已有证据：`media_command_controller` `[U] PASS(52)`，关联 key/switch、menu/app、display unit 和音频单元回归已通过；尚未与 A media-service、B packet RX 和双板 top 形成端到端证据。

## 2. 公共视频接口

B → 集成层提供 raw framebuffer/media stream：

```text
pix_clk / pix_rst_n
fb_pixel_valid / fb_pixel_data[23:0]
frame_boundary / underflow_sticky / protocol_error
```

集成层只生成一套 canonical raster sideband：

```text
in_valid / in_data[23:0]
in_frame_start / in_line_start / in_line_last
frame_boundary
```

所有 C 参数（OSD、亮度、对比度、缩放模式、transition、audio_enable）在 `frame_boundary` 快照，一帧内保持不变。C 的处理链不能把任意 backpressure 传回 B；需要暂停时使用固定深度 FIFO/line buffer 或切换 fallback。

## 3. 文件所有权

C 线可修改：

```text
src/display/*.v（hdmi_* protected/golden boundary 除外）
src/audio/**  src/interact/**  src/app/**
sim_tb/display/**  sim_tb/audio/**  sim_tb/interact/**  sim_tb/app/**
```

C 线不得修改：

```text
src/storage/**  src/framebuf/**
src/display/hdmi_video_adapter.v  src/display/hdmi_framebuffer_scanout.v
src/top/**  constraints/**  FPGA_Competition_HDMI.al
```

需要公共接口变化时，先在 mock/canonical contract 中说明，再由集成负责人统一合并；C 不新增底层 `load_request` 或 `framebuffer_base` 端口。

## 4. 控制面契约

C 只产生高层意图：

```text
media_cmd_valid / media_cmd_ready
media_cmd_image_id / media_cmd_mode
mode / transition_mode / osd_enable
contrast / brightness / emergency / audio_enable
config_valid / config_epoch
```

coordinator 负责把 `media_cmd` 转成 SPI 命令、credit 和提交请求：

```text
key/menu/app -> media_cmd -> M coordinator -> SPI -> S media service
S descriptor/status -> SPI RX -> coordinator -> status UI
```

C 不等待 A 的内部 writer 信号，也不修改 B 的 front/back metadata；C 只消费 `ready/status/error/frame_boundary`。

## 5. 统一节点中的 C 线任务

| 统一节点 | C 线任务 | C 线完成证据 |
|---|---|---|
| `M0` | 回归现有 raster、enhance、scaler、transition、OSD、交互和 audio 单元；保留 P1-05A fixed-pattern bypass | 既有单元回归通过；`media_command_controller` `[U] PASS(52)` |
| `M1`（当前） | 冻结 `media_cmd`、SPI command/status、descriptor/credit 状态页、canonical sideband 和 1080p 参数快照；建立 coordinator mock | valid/ready payload 保持、busy 合并、status/error UI TB；不接真实 A/B |
| `M2` | 将 `media_cmd` 接入 640×480 双板第一闭环；实现基本选图、NEXT/PREV、PLAY/PAUSE、轮播和 pass-through UI | 命令一次完成、无半帧参数混合；与 mock packet 子链汇合 |
| `M3` | 适配 720p line/tile 输入、链路状态/credit/CRC/underflow UI 和 fallback；完成基础缩放 | 720p bring-up 下 canonical raster 连续、状态可见 |
| `M4` | 适配 1920×1080 raster：字体/图标/OSD、缩放、亮度/对比度、1080p audio timing 和资源预算 | 1080p 静态图 + UI 的 `[C]`、资源和时序记录 |
| `M5` | 视频播放控制、图片/视频切换、淡入淡出/擦除等转场、音频 pack/tone/可视化；所有模块可旁路 | 视频和转场不改变 sideband，不产生半帧；音频流自洽 |
| `M6` | 完成最终 UI 场景、应急页、双源转场演示、真板音频和回退控制 | 1.4 扩展逐项开启；异常可退回最近稳定源 |

C 线可以用 deterministic source 和 B 的 PRBS/mock 独立推进。只有节点汇合时才接入真实 A packet 和 B RX，避免 C 对未完成板间链路形成阻塞依赖。

## 6. 1.4 扩展顺序

```text
M2 pass-through/基础交互
 -> M3 缩放与状态页
 -> M4 Logo/OSD/字幕/实时参数
 -> M5 图片/视频转场与音频
 -> M6 音频可视化、应急页、双源场景
```

主板不为 1920×1080 额外分配完整 overlay framebuffer；优先使用字体 ROM、图标 ROM、矩形和逐像素合成。若链路只提供单路源，转场由从板预混合或 C 在主板缓冲中完成，C 仍不改变 B 的提交规则。

## 7. C 线验收门槛

1. 每个受影响模块有 Questa/ModelSim 回归；sideband、固定延迟和异步 reset 行为可复现。
2. 配置只在 `frame_boundary` 生效；active line 一拍一像素，不把任意 ready 传回 B。
3. 不能修改 P1-04C/P1-05A 的 PHY、PLL、reset、EDID 或 `axis_user/valid/last` cadence。
4. UI、交互、转场和音频都能独立旁路；双板链路故障时保留固定图案/上一帧/应急页。
5. C 线模块通过 `[U]` 不等于主板 1080p `[S]/[B]`；后两级由集成负责人在统一节点验收。
