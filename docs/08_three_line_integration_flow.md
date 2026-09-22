# 三线集成路线图

> 本文件是执行顺序图。A/B/C 的接口细节、文件所有权和单线验收分别见 `docs/05_line_A_media_plan.md`、`docs/06_line_B_framebuffer_plan.md`、`docs/07_line_C_presentation_plan.md`；实际证据等级以 `docs/03_plan_and_status.md` 为准。

## 1. 当前起点

| 已完成模块/链路 | 当前证据 | 还不能说明 |
|---|---|---|
| P0 `fat32_file_reader -> bmp_parser/bmp_pixel_stream -> framebuffer_writer` | `[C] PASS(1698)` | 不能说明真实 TF 已接入 active top |
| P1-05A `pattern_writer -> SDRAM -> CDC/prefetch/line buffer -> HDMI_B` | `[C-sub]`、TD6.2.1 `[S]`；历史真板 `[B]` | TD6.2.1 bitstream 仍需重新上板复测 |
| P1-05B `p1_media_framebuffer_loader -> mock cached APUG011` | `[U] PASS(225)` | 不能说明 640×480、A/B 换帧或 TF→HDMI 已完成 |
| `frame_buffer_manager`、按键/应用、显示处理、音频单模块 | 各模块已有 RTL/TB | 尚未组成 P1-05B 系统闭环 |

当前架构只有一条运行时数据链：

```text
C 用户命令
    -> 集成 coordinator
    -> A TF/FAT32/BMP
    -> B back framebuffer / SDRAM
    -> B front framebuffer readout
    -> 集成 raster adapter
    -> C 表现层
    -> 冻结的 P1-04C/APUG092/HDMI
```

A 的 `p1_media_framebuffer_loader` 内部拥有唯一 `framebuffer_writer`。B 只拥有 front/back、SDRAM sink、读出和安全换帧；C 只产生用户命令和处理 RGB。任何阶段都不能增加第二个 writer、第二套 `done` 或第二套行帧 sideband。

## 2. 路线图总览

```text
R0 契约与 mock
  ↓
R1 A loader + B sink + manager 事务桥
  ↓
R2 A 真实目录/TF + B 写入链
  ↓
R3 B 动态读出 + 安全换帧
  ↓
R4 C pass-through + 两键轮播
  ↓
R5 P1-05B 图片 active top 与真板闭环
  ↓
R6 HDMI 基础音频
  ↓
R7 扩展功能
```

路线图中的“集成”都是一个明确的合并点；合并点通过后，后续工作才能建立在该结果上。

## 2.1 一页式执行路线图

下面的表只回答三个问题：先把什么接起来、通过后哪几条线继续并行、下一次集成的入口是什么。详细接口和验收条件仍看后面的 R0～R7。

| 节点 | 进入条件 | 本次集成动作 | 集成通过后，三线继续做什么 | 下一节点 |
|---|---|---|---|---|
| I0 契约 | P0 媒体链、P1-05A、P1-05B loader 单测均可回归 | 冻结 `media_cmd`、`load_*`、`mem_wr_*`、地址布局、`frame_boundary` 和唯一 writer 规则，跑通 fake coordinator | A：catalog/provider 契约；B：write fence 与动态读接口；C：`media_cmd`/按键 mock | I1 |
| I1 写事务 | A loader + fake sector provider；B mock sink/manager | 把 `A loader.mem_wr_*` 接到 `B sink`，把 loader 完成经 fence 接到 manager，一次命令只产生一次 start/done | A：640×480 provider-realistic；B：写入压力与错误注入；C：命令握手 | I2 |
| I2 真实写入 | I1 通过，loader 的固定尺寸回归通过 | 把 `TF/SPI → FAT32/catalog → A loader → B back buffer` 接起来，先只验证写入，不接 C 特效 | A：真实 TF、4 图、重试/超时；B：SDRAM refresh/read-priority 压测；C：下一张、启停轮播、周期配置 | I3 |
| I3 读出换帧 | I2 已能稳定写入 back buffer；P1-05A 读出链保持绿色 | 把 B manager 的 `read_base/read_geometry` 接入动态读 wrapper，完成安全换帧并输出 raw RGB | A：卡错误和重扫长稳；B：epoch、旧 front 释放、underflow 诊断；C：canonical raster pass-through | I4 |
| I4 基础交互 | I3 raw RGB 与 canonical raster 对齐 | 接入 C pass-through、下一张、启停自动轮播；增强、缩放、转场、OSD、音频均旁路 | A：媒体长稳；B：P1-05A rollback/STA 准备；C：交互回归和固定延迟验证 | I5 |
| I5 图片真板 | I4 RTL 子链通过，P1-05A rollback 可构建 | 集成负责人唯一修改 active top/工程/约束，重新 STA、BitGen、上板验证 4 图和轮播 | A/B：异常恢复、资源和时序复核；C：PCM/audio adapter | I6 |
| I6 基础音频 | I5 已取得图片播放的 `[C]`、`[S]`、`[B]` 证据 | 把 C PCM/test tone 接入 APUG092 audio/Data Island，重新 STA、BitGen、真板验证 | A/B：图像与音频长稳；C：一次只开一个扩展功能 | I7 |
| I7 扩展 | I6 通过，竞赛基础四项闭环 | 依次开启 OSD、单路增强、转场、缩放/双路读服务等，每项独立回归并保留 rollback | 三线只在已通过的节点上继续扩展，不能把扩展依赖倒灌回 A/B 契约 | — |

执行规则：I1 之前不接真实卡和 active top；I2 之前不讨论四图真板；I3 之前 C 只做命令和 pass-through；I5 之前不把任何模块单测或 BitGen 成功写成 P1-05B 完成。每个节点失败时回退到上一个绿色节点，再修复本节点，不跨节点堆叠问题。

**当前状态：** 目前已有的是 P0/P1 证据和这份路线图，I0/I1 的公共 coordinator、fake sink、write-fence harness 尚未取得新的集成 PASS。因此当前实际下一步是先完成 I0 契约测试，再完成 I1 的 A loader→B sink 事务桥；不能直接跳到 I2 的真实 TF 或 I5 的 active top。

## 3. 逐步执行路线

### R0：冻结契约，建立可运行的替身

**已具备：** P0 媒体格式、P1-05A 显示基线、P1-05B loader 单元测试。

**本次完成：**

```text
C media_cmd
  -> coordinator mock
  -> A loader mock
  -> B manager/mock sink
  -> fake writer_done/ok
```

冻结 640×480、24-bit BI_RGB、`0x00RRGGBB`、A/B 地址、`mem_wr_valid/ready`、`load_start/ready/done/ok`、`frame_boundary` 和 raw/canonical video stream 的定义。把 manager 的历史 `writer_start` 标为遗留端口，不能连接第二个 writer。

**并行开发：**

- A：整理目录表和 TF provider 的输入/输出契约；
- B：实现 manager completion bridge、写入 fence 的 mock 和动态读出接口草案；
- C：实现 `media_cmd`、按键事件、固定周期轮播的 mock；
- 集成：维护 coordinator、fake sink、golden raster adapter 的公共 harness。

**通过条件：** 单条 mock 链能完成一次 `start -> mem_wr -> done -> pending_swap -> frame_boundary -> swap`，且一次命令只有一次 start/done。通过后进入 R1。

### R1：先把已实现的 A loader 接到 B manager

**已具备：** A 的 `p1_media_framebuffer_loader` `[U] PASS(225)`；B 的 `frame_buffer_manager` 单元能力；B 的 SDRAM abstract sink。

**本次集成：**

```text
A p1_media_framebuffer_loader.mem_wr_*
    -> B write sink/mock SDRAM
A loader.done/ok + write_fence
    -> B manager.writer_done/writer_ok
    -> pending_swap
```

此阶段使用 mock sector provider 和 mock/fixed readout，不接 active top，不接 C 特效。

**并行开发：**

- A：把 loader 的 17×12 provider-realistic 测试扩展为固定 640×480 事务，保留 backpressure 和错误注入；
- B：完成 write sink、completion bridge、write fence 和重复 start/done 断言；
- C：完成 `media_cmd` 到 coordinator 的命令握手，但仍使用 fake display result；

**通过条件：** 写入完成必须经过 fence 才能进入 `pending_swap`；失败帧不污染 front；不出现双 writer。通过后，A/B 可以继续真实 TF 和动态读出，C 可以独立继续基础交互。

### R2：把真实 TF 目录和媒体 provider 接入 A/B 写入链

**已具备：** R1 的 A loader + B sink 事务桥。

**本次集成：**

```text
TF/SPI provider
  -> FAT32 mount/catalog
  -> image_id 查表
  -> A p1_media_framebuffer_loader
  -> B back buffer write
```

A 需要补齐真实卡初始化、目录扫描和 catalog。当前 `fat32_scan` 只覆盖根目录第一簇第一扇区，因此 R2 的首版卡镜像必须明确放置至少 4 个可识别 8.3 BMP 项，并对坏项、删除项和非 BMP 项做筛选。

**并行开发：**

- A：真实 TF provider、目录表、至少 4 个图片的 metadata 和 640×480 BMP 装载；
- B：用真实写流压测 read-priority、writer FIFO、SDRAM refresh 和写入 fence；
- C：完成两个按键语义：下一张、启停自动轮播，并输出 `media_cmd`，不直接触发 loader；

**通过条件：** 不少于 4 幅图片可被自动发现；逐幅写入 back buffer 的 RGB golden 正确；坏文件不产生 `load_ok`；C 命令在 busy 时有明确暂存或拒绝结果。通过后进入 R3。

### R3：把 B 的动态读出和安全换帧接入 A/B 子链

**已具备：** R2 的真实 A→B 写入链；P1-05A 固定 pattern 读出链。

**本次集成：**

```text
B manager.read_base/read_geometry
  -> dynamic read wrapper
  -> 已验证 CDC/prefetch/line buffer
  -> B raw RGB stream
```

必须处理 `p1_sdram_hdmi_pipeline` 当前 `FRAME_BASE=0` 固定参数、旧行预取、outstanding response、line buffer 失效和新 descriptor 的原子提交。不能只替换一个 base 信号。

**并行开发：**

- A：继续完善卡错误、重试、重扫和 provider timeout；
- B：完成 dynamic read、epoch、safe swap、旧 front 释放和 `underflow/protocol_error` 诊断；
- C：完成 canonical raster pass-through wrapper，固定 RGB 处理延迟；

**通过条件：** A/B/A 图片循环写入和显示稳定；swap 只发生在安全 frame boundary；一帧内 read base/geometry 不变；旧 front 未释放前不能再次写入；raw RGB 与 raster sideband 对齐。通过后进入 R4。

### R4：先接 C 的旁路和基础交互

**已具备：** R3 的真实 A/B raw RGB stream 和 canonical raster adapter；C 的 `media_cmd`、按键和应用状态。

**本次集成：**

```text
B raw RGB
  -> golden-raster adapter
  -> C pass-through
  -> 冻结 HDMI cadence
C next/play-pause
  -> media_cmd
  -> coordinator
```

此阶段只接 pass-through、下一张、启停轮播和可配置周期。`enhance`、`scaler`、`transition`、OSD 和音频全部保持 bypass。

**通过条件：** 至少两键行为正确；手动下一张和自动轮播都只在安全换帧后生效；无撕裂、无持续 underflow、无半帧参数混合。通过后进入 R5。

### R5：P1-05B 图片 active top 与真板闭环

**已具备：** R4 的 A/B/C RTL 子链和 P1-05A rollback。

**本次集成：** 集成负责人唯一修改 active top、工程和约束：

1. 先下载并复测 P1-05A TD6.2.1 bitstream；
2. 再接真实 TF/A loader、B dynamic read、C pass-through；
3. 保留固定 pattern fallback 和 HDMI rollback；
4. 重新执行 `read_design -> synthesis -> placement -> routing -> final STA -> BitGen`；
5. 真板验证至少 4 幅图片、手动切图、自动轮播、无明显撕裂和异常恢复。

**通过条件：** P1-05B 图片基础闭环取得新的 `[C]`、`[S]`、`[B]` 证据。此时仍不能把 HDMI 音频写成已完成。

### R6：接入竞赛基础 HDMI 音频

**已具备：** R5 的真实图片播放；C 的 `tone_gen`/`hdmi_audio_pack` 单模块结果。

**本次集成：**

```text
C PCM/test tone
  -> integration audio adapter
  -> APUG092 audio input/Data Island
  -> HDMI display/speaker
```

音频不能因为 TF 忙或图片切换而停止；音频时钟、sample valid、采样率和左右声道必须保持一致。

**通过条件：** 图像显示同时可听到可识别且稳定的 HDMI 测试音/提示音；重新完成 STA、BitGen 和真板验证。R6 通过后，才算满足选题基础四项。

### R7：基础闭环之后再做扩展

扩展按一次只开一个功能的顺序推进：

```text
OSD/亮度对比度
  -> 单路增强
  -> 淡入淡出或擦拭
  -> 缩放/双路读服务
  -> 音画联动
  -> 启动、资源、鲁棒性优化
```

每个扩展都有独立 mock、Questa、综合和 rollback；不回改 P1-05A HDMI low-level，不把扩展依赖倒灌成 A/B/C 的循环依赖。

## 4. 三线并行安排

| 当前集成点 | A 线下一项 | B 线下一项 | C 线下一项 | 下一集成点 |
|---|---|---|---|---|
| R0 mock 契约 | catalog/provider 接口 | fence/dynamic-read 接口 | media_cmd/按键 mock | R1 |
| R1 A loader + B sink | 640×480 provider-realistic | write fence + 压测 | 命令握手 | R2 |
| R2 真实 A/B 写入 | 真实 TF、4 图、错误恢复 | 边读边写预算 | 两键轮播、周期配置 | R3 |
| R3 B raw readout | provider robustness | safe swap/epoch | canonical pass-through | R4 |
| R4 C pass-through | 卡与目录长稳 | P1-05A rollback/STA准备 | 基础交互回归 | R5 |
| R5 图片真板 | 图片长稳/异常恢复 | 资源和时序复核 | PCM/audio adapter | R6 |
| R6 基础四项完成 | 资源/鲁棒性 | audio/display 长稳 | 选一项扩展 | R7 |

关键原则是：每次集成只合并已经通过当前门禁的模块；集成完成后，下一批模块才以该结果为新基线继续开发。这样 A 不需要等待 C 的特效，C 不需要等待真实 TF 才能做交互，B 也不需要重新实现 A 的 writer。

## 5. 合并与回退规则

推荐合并顺序：

```text
R0 contract/mock
 -> R1 A-loader/B-sink transaction bridge
 -> R2 A catalog/TF/provider
 -> R3 B dynamic-read/safe-swap
 -> R4 C pass-through/basic interaction
 -> R5 top/constraints/STA/BitGen/board
 -> R6 HDMI audio
 -> R7 extensions
```

每次只合并一个集成候选；失败时回退到上一个绿色路线节点。P1-05A fixed-pattern rollback 必须始终可构建。任何 active-netlist 变更都必须重新执行完整 STA；当前 P1-05A 的 HWNS 只有 `+0.003 ns`，不能继承为后续设计的时序裕量。

## 6. 完成定义

### P1-05B 图片闭环

- 自动发现并装载至少 4 幅 640×480、24-bit BMP；
- A/B framebuffer、write fence、safe swap 和动态读出通过；
- 下一张、启停自动轮播和可配置周期通过；
- HDMI 显示连续、清晰，无明显花屏、持续 underflow 或撕裂；
- 当前工具链的 STA、BitGen 和真板证据齐全。

### 竞赛基础闭环

除上述图片闭环外，还必须有 R6 的图像同时 HDMI 音频真板证据。`tone_gen` 或 `hdmi_audio_pack` 单测、BitGen 成功和 OSD 演示不能替代音频板级验收。
