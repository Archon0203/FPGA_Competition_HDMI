# C 线计划：主板 UI、图像处理、交互与 HDMI 音频

> 负责人：张宗，同时负责集成。C 线全部面向主板最终输出：图片轮播/切换、转场、字幕和 OSD、亮度/对比度等图像参数、精美 UI、HDMI 音频、音画同步和音频可视化。C 线不解析 TF，不实现板间 packet，也不把视频播放作为目标。

## 当前位置

`M2` 已证明基本的 NEXT/PREV、自动轮播和主板图片输出。下一步进入 `M3-C`：以 1920×1080 raster 和 A/B 的真实图片提交接口为边界，完成可旁路的 UI/图像处理骨架；随后在 `M4/M5` 逐项加入转场、字幕、参数调整和音频。

## 1. C 线责任边界

```text
A catalog/status -> coordinator/media_cmd -> B image_commit/raster
                                           -> image processing
                                           -> UI/OSD/subtitle
                                           -> HDMI audio + visualization
```

C 线拥有：

- 按键、外接旋钮 A/B 相位解码、消抖、选择转轮和确认 FSM；
- `OPEN/NEXT/PREV/PLAY/PAUSE` 高层命令和轮播计时；
- 过渡动画（淡入、擦除、滑动等）和切换期间的上一帧保持；
- 字幕、状态栏、图片编号、加载/错误提示和精美 UI 图层；
- 亮度、对比度、色彩/简单缩放等逐像素参数，参数只在 `frame_boundary` 快照；
- PCM/提示音/背景音样本产生、HDMI 音频配置、音画同步策略；
- 由同一音频样本计算振幅/频段柱状图并叠加到 1080P 图像。

C 线不拥有：

- TF/FAT32/BMP 解析；
- GPIO packet、CRC、CDC、SDRAM writer、front/back 地址；
- APUG092 protected core、HDMI pin、时钟约束和两个顶层工程。

## 2. 不形成循环依赖的接口

### C 从 A 读取媒体事实

```text
catalog_valid / catalog_count / catalog_epoch
descriptor(image_id, width, height, pixel_format)
source_busy / source_done / source_error
```

因此 C 可以决定转轮边界和图片标题，但 A 不等待 UI 生成。C 发送 `OPEN(image_id)` 后，只有收到目标图片的 `source_done + image_commit` 才开始下一次轮播计时。

### C 从 B 读取显示事实

```text
rgb_valid/rgb_data
frame_boundary / image_commit
underflow_sticky / protocol_error / link_ready
```

B 先输出可旁路的 canonical raster；C 不把任意 backpressure 传回 B。需要多拍处理时使用固定深度 FIFO/line buffer，active line 不暂停。

### 配置生效规则

亮度、对比度、转场模式、字幕内容、UI 页面和音频配置全部写入 shadow registers，在 `frame_boundary` 一次性切换。这样不会出现一帧上半部分和下半部分使用不同参数。

## 3. 节点任务

| 节点 | C 线任务 | 完成条件 |
|---|---|---|
| `M0` | 保留已有 `media_command_controller`、image_enhance、transition、OSD、audio_visual 单元回归 | 既有 `[U]` 证据可复现 |
| `M1` | 冻结 `media_cmd`、descriptor/status、frame-boundary 和配置快照；完成双板控制面 | Master 控制链真板通过，当前已完成 |
| `M2` | 接入真实 catalog/status；NEXT/PREV、PLAY/PAUSE、自动轮播；加载/错误页 | 640×480 双板主板输出和轮播 `[B]`，当前已通过 |
| `M3` 下一节点 | 1920×1080 raster 适配；UI/OSD/图像增强可旁路；按键/旋钮选择 FSM 接口冻结 | 固定图 + UI + 亮度/对比度在 1080P raster 上无破坏性旁路 |
| `M4` | 淡入/淡出/擦除/滑动；字幕和状态栏；首次启动 Loading / 缺卡页，切图保持上一帧且不显示 Loading；资源预算 | 4 张图片切换无半帧、无 UI 越界，异常回退上一帧 |
| `M5` | HDMI PCM/提示音、音画同步、音频可视化、精美 UI 收口 | 音频样本、图像提交和可视化使用同一时间基准 |
| `M6` | 应急页、演示场景、参数预置、长稳和最终交互验收 | 选题 1.4 扩展逐项演示，故障可回退 |

## 4. 推荐交互闭环

```text
按键/旋钮确认
  -> 暂停轮播并锁定当前 image_id
  -> 显示选择转轮/缩略图和标题
  -> 旋钮改变 selected_id，按压确认
  -> C 发 OPEN(selected_id)
  -> A 返回 descriptor/ready，B 接收并安全提交
  -> C 收到 image_commit + source_done
  -> 执行所选转场，恢复轮播计时
```

旋钮尚未接入时，使用按键仿真接口开发；正式 GPIO 管脚、电平、消抖和 CDC 由集成负责人冻结后再上板。

## 5. 图像处理和 UI 分层

```text
B canonical RGB raster
  -> image enhance (brightness/contrast)
  -> transition compositor (old/new image)
  -> subtitle/status OSD
  -> audio visualization bars
  -> rounded panels/icons/loading/emergency UI
  -> APUG092 video input
```

每一级必须支持旁路。UI 优先使用字体 ROM、图标 ROM、矩形和逐像素合成，不为 1080P 额外复制完整 overlay framebuffer；如果资源不足，先降低动画复杂度，不能破坏基础图片输出。

## 6. HDMI 音频和音画同步

- C 线产生或读取 PCM 样本，使用 B/集成提供的 `audio_sample_tick` 和 HDMI audio ready 边界；
- 每次图片 `image_commit` 生成 `image_epoch`，音频场景在同一 epoch 开始/停止，避免画面已经切换而提示音仍属于上一张图片；
- 音频可视化只消费同一份 PCM 样本的包络/频段结果，不另建无法同步的测试源；
- APUG092 音频端口、N/CTS、I2S/IEC60958 细节由 B/集成按官方例程接入，C 提供可验证的样本和控制契约。

## 7. 文件所有权

C 线可修改：

```text
src/display/**（hdmi_* golden boundary 除外）
src/audio/**  src/interact/**  src/app/**
sim_tb/display/**  sim_tb/audio/**  sim_tb/interact/**  sim_tb/app/**
```

C 线不得直接修改：

```text
src/storage/**  src/dual_board/**  src/framebuf/**
src/display/hdmi_video_adapter.v  src/display/hdmi_framebuffer_scanout.v
src/top/**  constraints/**  两个长期 .al 工程
```

公共接口变化先写 contract，再由集成负责人协调 A/B 更新；C 不通过 UI 状态直接驱动 A 的 loader 或 B 的 swap。

## 8. C 线验收门槛

1. 每个图像、UI、交互和音频模块有独立 Questa 回归；参数更新只在 frame boundary 生效。
2. C 线 mock 通过只证明局部逻辑；真实图片目录、真实 `image_commit`、1080P raster 和 HDMI 音频必须在节点汇合时复测。
3. 转场、字幕、亮度/对比度和音频可视化均可旁路；链路异常时保持上一帧或显示应急页。
4. UI 合成不能改变 `rgb_valid/line_last/frame_boundary` cadence，不能把 backpressure 传回 SDRAM/板间链路。
5. C 线 `[U]/[C-sub]` 不等于最终双板 `[S]/[B]`；由集成负责人完成双 bitstream 和真板验收。
