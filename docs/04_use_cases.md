# 04 · 使用场景与演示设计

## 1. 产品场景

项目定位：**校园/园区信息发布与应急广播终端**。最终由 FPGA 独立完成 TF 读取、文件解析、framebuffer、显示处理、HDMI 音视频与交互，不依赖外部 CPU/MCU。

## 2. 当前已验证演示

### P1-04C · HDMI link baseline

HX4S20C HDMI_B `[B] PASS`，稳定八色条，证明 50 MHz board clock、HDMI PLL、APUG092、EG PHY、pin 与 monitor lock。

### P1-05A · SDRAM framebuffer baseline

P1-05A 已 `[S][B] PASS / CLOSED`。真板稳定显示：

```text
+--------------------------------------------------+
|                    WHITE BORDER                  |
|      RED                 |       GREEN           |
|---------------------- CYAN ----------------------|
|      BLUE                |       YELLOW          |
+--------------------------------------------------+
                         ^
                   MAGENTA vertical bar
```

该演示真实证明：

- internal SDRAM 可写入完整 640×480 RGB888 framebuffer；
- APUG011 sequential read bandwidth 足以支撑当前 640×480 raster；
- 150↔25 MHz ordered CDC 有效；
- line prefetch + ping-pong line buffer 可持续供数；
- framebuffer RGB 可通过冻结的 P1-04C HDMI cadence 稳定输出；
- 最终 bitstream 无可见抖动、抽搐、撕裂或移动黑线。

这个测试图与经典四色标志在视觉上有巧合，但项目中它的定义是 **deterministic framebuffer diagnostic pattern**，用于同时验证象限、RGB 组合、frame border、水平/垂直中心线和地址顺序，不作为品牌 Logo 使用。

## 3. P1-05A timing caveat

当前 TD5.6.2 已 0 setup / 0 hold，WNS `+0.068 ns`，因此可以正式作为稳定 baseline；但 150 MHz timing margin 较薄。答辩和开发记录应表述为“timing closed”，不要表述为“有较大频率余量”。

**TD6.2.1 迁移说明：** 官方要求已切换到 TD6.2.1。当前 source tree 正在进行针对新工具链的 timing optimization；在重新取得 TD6.2.1 final STA 前，不将新的 source candidate 宣称为新的 timing-closed 证据。P1-05A 的功能演示仍以历史真板 framebuffer golden baseline 为依据。

## 4. 下一演示：P1-05B 真图片播放

```text
TF
 ↓
FAT32
 ↓
BMP
 ↓
SDRAM A/B framebuffer
 ↓
P1-05A display pipeline
 ↓
HDMI
```

目标：真实 BMP、手动切图、自动轮播、frame-boundary swap、不撕裂。

只有 P1-05B 真板通过后，才能对外表述“TF→SDRAM→HDMI 图片播放完成”。

## 5. 常规信息发布

最终：TF 保存公告 BMP、海报和短视频帧序列；自动轮播/按键切换；OSD 显示序号、模式、状态；可选 HDMI 提示音。

## 6. 应急广播

```text
Emergency trigger
   ↓
local emergency framebuffer
   ├─ full-screen warning
   ├─ high-priority OSD
   ├─ HDMI alert tone
   ├─ beep
   └─ LED status
```

应急页优先使用已准备好的本地 framebuffer，不依赖当前 TF 请求即时完成。

## 7. 技术展示顺序

1. P0 RTL media chain `[C]`；
2. P1-02 APUG011 150 MHz `[S]`；
3. P1-04C HDMI `[B]`；
4. P1-05A SDRAM framebuffer `[S][B]`；
5. P1-05B TF/BMP `[B]`（取得后）；
6. OSD/audio/transition 等扩展。

## 8. UI 分层

| Priority | Layer | Content |
|---|---|---|
| UI-L3 | Emergency | 全屏应急警示 |
| UI-L2 | Text/OSD | 状态栏、时间、滚动文字、参数 |
| UI-L1 | Audio Visual | 振幅/频带 |
| UI-L0 | Base Media | BMP/短视频基础画面 |

P1-05A 已完成 UI-L0 的真实 SDRAM→HDMI 基础数据通路；P1-05B 将把固定测试源替换为真实 TF/BMP 内容。

## 9. 分辨率边界

```text
640×480 : 当前稳定 baseline
1280×720: 独立 timing optimization
1920×1080 / 双板: P4 feasibility
```

当前便携屏没有 input timing OSD，面板是否把 640×480 输入内部缩放为 1920×1080 全屏暂无法直接确认；色块边缘轻微 halo 也暂记为显示器 scaler/锐化/面板响应的非阻塞观察项。

## 10. 当前对外口径

### 可以说

- P0 media core 已通过 RTL chain；
- APUG011 backend 已通过 150 MHz TD；
- P1-04C HDMI_B 已真板通过；
- **P1-05A 已完成 internal SDRAM framebuffer → HDMI 的 Questa、TD timing、BitGen 和真板闭环；**
- 当前 combined STA 为 0 setup / 0 hold，WNS +0.068 ns；
- 真板显示稳定，无可见 tearing/jitter/scanline underflow。

### 还不能说

- TF→SDRAM→HDMI 已完成；
- 720p 已支持；
- 1080p 已支持；
- P1-05A 已取得 `[L]` 长稳等级。
