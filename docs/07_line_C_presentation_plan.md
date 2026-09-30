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

## 2.1 C 线不能忽略的 A/B 依赖

C 线分成“可用 mock 独立开发”和“必须真实合并验收”两部分：

| C 模块 | 可先用 mock 开发的部分 | 真实合并的必要输入 |
|---|---|---|
| 按键滤波、旋钮 quadrature decoder、选择 FSM | 完全可独立 | 无；但最终 GPIO pin/CDC 由集成负责人确认 |
| 转轮、字体、图标、OSD、参数页 | deterministic raster + 固定 catalog | B 的 canonical raster；A 的 catalog 条目、类型和数量 |
| `media_command_controller` / coordinator | mock `catalog_valid/count`、mock status | A 的 `catalog_epoch/descriptor/ready/busy/done/error` |
| 缩放、转场、音频时序 | PRBS/固定帧 | B 的 `frame_start/line_start/line_last/frame_boundary` 和真实 `frame_id` |
| 图片/视频切换验收 | mock source 可测状态机 | A 的媒体完成/错误状态 + B 的无欠载提交结果 |

初步交互方案按“按键进入选择 → 暂停当前源 → 旋钮浏览 → 按压确认 → OPEN 新源 → 首帧安全提交 → 恢复播放”实现。旋钮不是板载资源，默认采用外接增量式正交编码器 A/B + 按压开关，接入 40-pin GPIO；必须先完成 pin ownership、输入电平、消抖和 CDC 约束，不能把未确认的管脚写进正式约束。若旋钮硬件尚未到位，M1/M2 使用按键仿真接口，不能因此改变 A/B 契约。

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
| `M1`（当前） | 冻结 `media_cmd`、SPI command/status、descriptor/credit 状态页、canonical sideband 和 1080p 参数快照；建立 coordinator mock；完成按键/旋钮输入抽象、选择 FSM、转轮绘制 mock | valid/ready payload 保持、busy 合并、status/error UI TB；明确 A/B 依赖端口；不宣称真实媒体或真实 raster 已接入 |
| `M2` | 将 `media_cmd` 接入 A 的真实 catalog/status 和 B 的 640×480 双板第一闭环；实现基本选图、NEXT/PREV、PLAY/PAUSE、轮播和 pass-through UI | 一次命令对应一次 OPEN；收到 A 的 ready/done/error；B 的真实 frame_boundary 才允许提交；无半帧参数混合 |
| `M3` | 接入 B 的 720p line/tile 输入、链路状态/credit/CRC/underflow UI 和 fallback；完成基础缩放；接入 A 的媒体类型/帧数 descriptor | 720p bring-up 下 canonical raster 连续、状态可见；A/B 状态和 UI 不循环等待 |
| `M4` | 适配 1920×1080 raster：字体/图标/OSD、缩放、亮度/对比度、1080p audio timing 和资源预算 | B 的 1080p profile + A 的 1080p descriptor/数据均已通过；1080p 静态图 + UI 的 `[C]`、资源和时序记录 |
| `M5` | 视频播放控制、图片/视频切换、淡入淡出/擦除等转场、音频 pack/tone/可视化；所有模块可旁路 | 视频和转场不改变 sideband，不产生半帧；音频流自洽 |
| `M6` | 完成最终 UI 场景、应急页、双源转场演示、真板音频和回退控制 | 1.4 扩展逐项开启；异常可退回最近稳定源 |

C 线可以用 deterministic source、固定 catalog 和 B 的 PRBS/mock 独立推进；这只证明 C 的局部逻辑。节点汇合时按“先 A descriptor/status，再 B canonical raster，再接入 C coordinator/UI”顺序接入真实模块，避免出现 C 等 A、A 又等 C 的循环依赖。C 只发高层命令，A 只返回媒体事实，B 只返回显示事实。

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
