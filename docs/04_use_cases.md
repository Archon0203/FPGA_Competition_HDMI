# 04 · 使用场景与演示设计

## 1. 产品场景

项目定位：**校园/园区信息发布与应急广播终端**。最终由 FPGA 独立完成 TF 读取、文件解析、framebuffer、显示处理、HDMI 音视频与交互，不依赖外部 CPU/MCU。

## 2. 当前已验证演示

### P1-04C · HDMI link baseline

HX4S20C HDMI_B `[B] PASS`，稳定八色条，证明 50 MHz board clock、HDMI PLL、APUG092、EG PHY、pin 与 monitor lock。

### P1-05A · SDRAM framebuffer baseline

P1-05A 的功能链和 TD6.2.1 真板基线已通过；当前 TD6.2.1 active top 已取得 routed `[S]` 和真板 `[B]`。

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

## 3. P1-05A timing status

当前 TD6.2.1 final routed report（2026-09-21）为 STA coverage `99.17%`、SWNS `+0.599 ns`、STNS `0`、HWNS `+0.003 ns`、HTNS `0`，setup/hold 违例端点均为 0。硬件最小裕量只有 3 ps，答辩和开发记录应表述为“当前 routed STA 无违例”，不要表述为“有较大频率余量”。TD5.6.2 的 WNS `+0.068 ns` 只作为历史 closeout 记录。

**板级边界：** 当前 TD6.2.1 bitstream 已重新下载并显示正常；P1-05A 已取得当前工具链 `[B]`。当前 run 仍保留两个 SDRAM location warning 和一条 local clock routing warning。

## 4. 下一演示：双板媒体第一闭环

```text
从板 TF -> FAT32/BMP -> media service -> SPI/GPIO packet
                                      -> 主板 buffer/safe commit -> HDMI
```

M2 以至少 4 幅 640×480 BMP 完成双板第一闭环，覆盖手动切图、自动轮播、frame-boundary 提交和错误回退。该媒体规格用于证明选题基础能力，不单独搭建单板 P1-05B 开发路线；主板链路与接口从 M1 起就按最终双板架构定义。

只有 M2 双板真板闭环通过后，才能对外表述“TF 图片经双板输出完成”。

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

1. P0/P1-05A 已有 RTL、TD 和真板证据；
2. M1 双板协议/A-B-C 可视化控制闭环（已真板 PASS，Slave-HDMI 为临时诊断 profile）；
3. M2 双板 TF/BMP 640×480 第一闭环；
4. M3 1080p packed-YUV422 等效数据链吞吐门禁（720p 仅可选排错）；
5. M4 双板媒体到主板 1080p 静态图和 UI；
6. M5/M6 视频、1.4 扩展、转场、音频及最终真板验收。

## 8. UI 分层

| Priority | Layer | Content |
|---|---|---|
| UI-L3 | Emergency | 全屏应急警示 |
| UI-L2 | Text/OSD | 状态栏、时间、滚动文字、参数 |
| UI-L1 | Audio Visual | 振幅/频带 |
| UI-L0 | Base Media | BMP/短视频基础画面 |

P1-05A 已完成 UI-L0 的真实 SDRAM→HDMI 基础数据通路；P1-05B 将把固定测试源替换为真实 TF/BMP 内容。

## 8.1 交互闭环与依赖

目标交互由主板 C 线实现：

```text
按键进入选择
  -> 暂停当前播放并锁定当前 frame
  -> 显示图片/视频转轮
  -> 旋钮 A/B 方向改变 selected_id
  -> 旋钮按压确认
  -> C 发 OPEN(selected_id)
  -> A 返回 descriptor/ready
  -> B 在 frame_boundary 安全提交首帧
  -> C 收到 done/error 后恢复播放或回退上一帧
```

其中转轮绘制和输入 FSM 可以先用 mock 开发；`selected_id` 的合法范围和媒体类型依赖 A 的 catalog/descriptor，首帧是否可提交及是否欠载依赖 B 的 `frame_boundary/underflow/protocol_error`。旋钮采用外接增量式编码器，优先接 40-pin GPIO；在管脚、电平和 CDC 尚未冻结前只使用按键仿真，不把临时管脚写入正式约束。

## 9. 分辨率边界

```text
640×480 : P1-05A rollback；也是 M2 双板第一媒体规格
1280×720: 仅在 M3 排错时可选，不作为验收节点
1920×1080 / 双板：M1 起即按此架构设计，M4～M6 完成主目标验收
```

双板演示采用主从结构：主板负责最终 HDMI、UI/OSD、缩放、转场和音频；从板负责 TF/视频读取、媒体预取和帧/行/tile 生产。主板通过 SPI 下发命令和 credit，从板通过待验证的 source-synchronous GPIO 数据面返回媒体包。M1-B0 已取得三线 UART 双板真板双向通信证据，正确排针为 J1-8(TX/J13) ↔ 对端 J1-4(RX/F13) 并共地；但这只证明控制面，不等于媒体数据面。M1ABC 的 Master 控制 / Slave HDMI 可视集成已经真板 PASS；aggregate Questa 和两角色 final STA 数值仍需补档。M2 起显示职责回到最终架构：Master HDMI，Slave 媒体生产。source-synchronous 媒体链与真实 1080p 仍必须逐级取得 RTL、STA 和真板证据。

当前便携屏没有 input timing OSD，面板是否把 640×480 输入内部缩放为 1920×1080 全屏暂无法直接确认；色块边缘轻微 halo 也暂记为显示器 scaler/锐化/面板响应的非阻塞观察项。

## 10. 当前对外口径

### 可以说

- P0 media core 已通过 RTL chain；
- APUG011 backend 已通过 150 MHz TD；
- P1-04C HDMI_B 已真板通过；
- **P1-05A 已完成 internal SDRAM framebuffer → HDMI 的 Questa、TD6.2.1 routed `[S]`、BitGen 和当前工具链真板闭环；**
- 当前 TD6.2.1 final STA 为 0 setup / 0 hold，SWNS +0.599 ns、HWNS +0.003 ns；
- TD6.2.1 BitGen 已生成 bitstream，重新上板后显示稳定，无可见 tearing/jitter/scanline underflow；
- M1 三线 UART 双板控制通信已经真板通过，M1ABC Master 控制 Slave HDMI 的可视化 board gate 也已 PASS；
- 1.4 全部扩展与 1920×1080 主目标已进入路线，但尚未取得对应最终证据。

### 还不能说

- TF→SDRAM→HDMI 已完成；
- 1280×720/1080p 已支持；
- 1080p 已支持；
- 双板媒体链路已通过；
- P1-05A 已取得 `[L]` 长稳等级。
