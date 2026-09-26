# C 线计划：表现层、交互与音频

> 双板迭代说明：C 线部署在主板 M。C 线只消费主板 canonical raster/source stream，不直接读取从板 TF，不直接操作板间 GPIO。C 线产生高层 `media_cmd`，由主板 coordinator 转成 SPI 控制命令。

## 1. 依据、目标与边界

C 线对应选题中的信息发布表现层：OSD/字幕、亮度与对比度、缩放、转场、按键/拨码交互、应用状态、提示音和音频可视化。P0 媒体解析、P1-05A SDRAM 读写、APUG011、TF 物理接口和 HDMI PHY 不属于 C 线所有权。

P1-04C/P1-05A 已冻结的 APUG092 cadence、HDMI PHY/PLL、reset、EDID/IIC 和 640×480 timing 是 C 线的 golden boundary。C 线只能在 RGB 数据和应用配置层工作；任何 cadence 或 PHY 修改都必须离开 C 线 PR，由集成负责人单独评审并重新取得 STA/板级证据。

## 2. 两层视频接口，禁止混用

### 2.1 B → integration：raw framebuffer stream

B 线交付：

```text
pix_clk / pix_rst_n
fb_pixel_valid
fb_pixel_data[23:0]
frame_boundary
underflow_sticky
protocol_error
```

它表示已从 SDRAM 读出的 RGB 数据和存储状态，不承诺 C 线的 `frame_start/line_start/line_last` sideband。

### 2.2 integration → C：canonical raster stream

集成层使用冻结的 P1-04C golden raster 产生：

```text
in_valid
in_data[23:0]
in_frame_start
in_line_start
in_line_last
frame_boundary
```

sideband 定义固定为：

| 信号 | 定义 |
|---|---|
| `frame_start` | 第一行第一 active pixel |
| `line_start` | 每行第一个 active pixel |
| `line_last` | 每行最后一个 active pixel |
| `frame_boundary` | 允许提交 metadata/swap 的安全事件，不等同于 `frame_start` |

B 不重新生成一套 C sideband，C 也不根据自己的计数器反向驱动 B swap。这样行帧边界只有一个权威定义。

## 3. 文件所有权

C 线可以修改：

```text
src/display/*.v（hdmi_* protected/golden boundary 除外）
src/audio/**  src/interact/**  src/app/**
sim_tb/display/**  sim_tb/audio/**  sim_tb/interact/**  sim_tb/app/**
```

C 线不得修改：

```text
src/framebuf/**  src/storage/**
src/display/hdmi_video_adapter.v  src/display/hdmi_framebuffer_scanout.v
src/top/**  constraints/**  FPGA_Competition_HDMI.al
src/vendor/**  FPGA_Competition_HDMI_Runs/**
```

需要调整公共 stream 或配置接口时，先更新 mock/canonical contract，由集成负责人统一合并；不要在 C 线 PR 中直接添加新的底层 `load_request` 或 framebuffer base 端口。

## 4. 控制与媒体命令契约

C 线只产生高层用户意图：

```text
media_cmd_valid
media_cmd_ready
media_cmd_image_id
media_cmd_mode
```

`media_cmd` 送给 integration coordinator；coordinator 根据 B 的 `load_ready` 分配 back buffer，并向 A 发 `load_start`。C 线不产生底层 `load_request`，不等待 A 的内部 writer 信号，也不直接写 SDRAM。

显示配置进入视频域时使用快照：

```text
mode / image_index / transition_mode
osd_enable / contrast / brightness
emergency / audio_enable
config_valid / config_epoch
```

配置在 `frame_boundary` 采样，一帧内部保持稳定。按键/系统时钟域的多比特配置必须通过握手、双寄存器快照或异步 FIFO 跨域，不能直接组合跨入 pixel clock。

## 5. 音频边界

C 线先交付自洽的 PCM sample stream 或 `hdmi_audio_pack` 子帧：数据、valid、采样率和音频时钟必须属于同一契约。最终 Data Island 注入和 APUG092 wrapper 仍由集成阶段处理。C 线不得为音频便利而修改 HDMI PHY、reset 或官方 packet cadence。

## 6. C 线分阶段计划

### C0：P0/P1 表现层回归基线

保持现有 `vga_timing`、`color_space`、`image_enhance`、`image_scaler`、`transition`、`osd_overlay`、`menu_fsm`、`app_scenario` 及 audio unit TB 通过。P1-05A fixed-pattern/bypass 作为输入替身。2026-09-25，`media_command_controller` 完成 QuestaSim 10.7c 单元回归 `PASS(52)`；关联的 key/switch、menu/app、display unit 回归均通过。

### C1：canonical stream 流水线

用 deterministic source 驱动：

```text
canonical source -> enhance -> scaler -> transition -> OSD -> sink
```

验证固定延迟、`frame_start/line_start/line_last` 不丢失、active line 一拍一像素、边界像素正确、参数只在 frame boundary 生效。C 处理链不能用 `ready` 把任意 backpressure 传回 B；需要缓存时使用固定深度 FIFO/line buffer。

### C2：交互与应用状态

把 key/switch filter 的事件转换为播放、暂停、上下张、应急和配置快照，并通过 `media_cmd_*` 发送用户意图。禁止 C 状态机直接启动 A writer 或修改 B 的 front/back metadata。

I0 已冻结的实现为 `src/app/media_command_controller.v`：当 `media_cmd_ready=0` 时保持当前 command payload，后续选图意图合并为 deferred command；应急状态只作用于主板本地 UI/提示音，不生成媒体 load command。该单元是 `[U] PASS(52)`，尚未与 coordinator、A loader 或 B manager 构成端到端系统链。I1 阶段 C 线只继续完成 `media_cmd` 到 coordinator mock/真实握手，不改变 A/B 写事务接口。

### C3：音频与可视化

先验证 tone、PCM pack、音频可视化和静音/应急提示音，再通过 mock audio sink 检查采样流稳定性。未经集成和真板证据，不宣称 HDMI 音频完成。

### C4：可旁路集成候选

提交一个可旁路的 pass-through/增强适配器。集成负责人先接 pass-through，再按 `enhance -> scaler -> transition -> OSD -> interaction -> audio` 逐项开启；任何时序下降都可关闭最近一项并保留 P1-05A rollback。

## 7. C 线验收门槛

1. 受影响模块 Questa/ModelSim 回归通过；
2. canonical sideband 和固定延迟在压力、暂停、异步 reset 下保持正确；
3. active line 无任意停顿，不能把 backpressure 传回 B；
4. 配置只在 frame boundary 更新，不能产生半帧混合参数；
5. 不改变 P1-04C/APUG092 的 `user/valid/last` cadence、PLL、PHY、reset 或 EDID；
6. 显示、交互和音频均可独立 bypass，且 C 线不形成对 A/B 的反向依赖。

## 8. 主板 UI 与 1.4 扩展顺序

C 线将官方 1.4 扩展全部纳入安全交付线，顺序固定为：

```text
C0 canonical raster/pass-through
 -> C1 Logo/OSD/字幕图层
 -> C2 亮度/对比度/实时参数快照
 -> C3 图片缩放适配
 -> C4 淡入淡出/擦除转场
 -> C5 音频可视化
```

主板使用字体 ROM、图标 ROM、矩形和逐像素合成实现 UI，避免为 1920×1080 再分配一张完整 overlay framebuffer。参数只能在 frame boundary 采样，一帧内保持稳定。转场的 A/B 源由 coordinator 从主板当前帧和从板下一帧服务中提供；若链路只能提供单路源，则由从板预混合后发送单路结果，C 仍只叠加 UI。

## 9. 双板命令边界

```text
key/menu/app_scenario -> media_cmd -> M coordinator -> SPI command -> S media service
S descriptor/status   -> M SPI RX   -> coordinator/status UI
```

C 线不得产生 `load_request`、`framebuffer_base`、GPIO packet 时钟或从板内部 sector 请求。C 线可以要求下一张、播放/暂停、转场模式、目标分辨率和应急画面，但具体 buffer 分配、credit 和提交时刻由 M/B 线控制。

## 10. 分辨率与回退

安全交付线以 1280×720 为目标；挑战线才开启 1920×1080。1080p 时 UI、OSD 和音频可视化必须在主板 profile 上独立通过综合、STA 和真板验证。若 1080p PHY 或板间数据面未收敛，C 线必须保留 720p 全部 1.4 功能和 P1-05A fixed-pattern rollback。
