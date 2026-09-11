# 02 · 实现目标与验收边界

## 1. 作品定位

作品名称：**《基于 EG4S20 的 HDMI 多媒体播放系统——校园/园区信息发布与应急广播终端》**。

目标是在 HX4S20C（EG4S20BG256）上，用 FPGA 完成媒体读取、缓存、显示处理、交互与 HDMI 音视频输出，**系统运行时不依赖外部 CPU/MCU**。PC 工具只用于赛前/部署前的内容制备，例如把素材转换成 BMP、`.vseq` 或字库，不参与设备运行时控制和算法处理。

硬件基线：EG4S20BG256，约 19,600 LUT / 19,600 FF，片内 SDRAM 2M×32 bit（约 8 MB），板载 TF、HDMI、50 MHz 时钟和交互外设。

## 2. 必做目标

| 目标 | 实现口径 | 最终证据 |
|---|---|---|
| 媒体读取 | TF/SD 读取图片；FAT32 8.3 文件索引；24-bit BMP 解析 | 真卡 `[B]` |
| 帧缓存 | 图片 A/B 双缓冲；后台加载与前台显示互斥；帧边界切换 | P0 `[C]` + 真 SDRAM `[B]` |
| 稳定显示 | **board-safe 640×480 首次点亮（已完成） + 1280×720 性能目标**；active line 连续，无 underflow/撕裂 | TD `[S]` + HDMI `[B]` + 长稳 `[L]` |
| HDMI 正式输出 | RGB888 → APUG092 → EG PHY → HDMI | `[B]` |
| 基础音频 | HDMI 测试音/提示音，后续可接 PCM | `[B]` |
| 人机交互 | 按键/拨码完成切换、播放状态、参数、应急模式 | 集成 `[C]` + `[B]` |
| 工程规范 | P0/P1 架构、CDC、官方约束、资源/时序报告、可重复回归 | `[S]` |

P0 已经证明了“文件流到稳定 RGB 行”的纯 RTL 基础链；后续工作的核心不是重复写这一链，而是把它接入真实 vendor/board 环境。

## 3. 高优先级加分目标

按“对展示价值 / 资源 / 风险”的综合性价比排序：

| 优先级 | 功能 | 现有基础 | 计划阶段 |
|---|---|---|---|
| 高 | OSD/字幕：时间、状态栏、滚动标语 | `osd_overlay [U]` | P2 |
| 高 | 亮度/对比度实时调节并显示参数 | `image_enhance [U]` + `menu_fsm [U]` | P2 |
| 高 | 图片/短视频适配到 1280×720 输出（缩放/居中/裁剪策略按资源选择） | `image_scaler [U]` | P2/P3 |
| 中 | 图片淡入淡出/擦拭转场 | `transition [U]` | P2 |
| 中 | 音频振幅/简易频带可视化 | `audio_visual [U]` | P2 |
| 中 | YUV444 `.vseq` 短视频片段 | `vseq_reader/vseq_yuv_unpack/color_space [U]` | P3 |
| 低/可选 | YUV420、省带宽格式、SDIO、1080p/双板可行性 | 有部分 `[U]` 组件；1080p 仅参数预留 | P4 |

## 4. 内容格式与数据目标

### 4.1 图片

P0 基线固定为：

- BMP 24-bit、BI_RGB、bottom-up；
- 行尾 4-byte padding；
- RGB 存储格式 `0x00RRGGBB`；
- P0 framebuffer 回归几何仍为 640×480；P1-04B 首次 board-safe 输出同样采用 working official 640×480。1280×720 保留为下一阶段性能目标，待 PLL/STA closure 后再升级为板级基线。

### 4.2 FAT32 / TF

基线目标：512-byte sector、SDHC/SDXC、8.3 short filename、fragmented FAT chain。当前 `fat32_file_reader` 已支持碎片链和 file-size 终止，但 `fat32_scan` 只覆盖根目录第一 sector；真正“任意卡插入即可播放”的鲁棒性必须到板级继续扩展和验证。

### 4.3 短视频

不实现 H.264/HEVC/MP4 压缩解码。短视频采用：

```text
PC 离线转帧 → .vseq 原始帧序列 → FPGA 读取/缓存/颜色转换/缩放/显示
```

当前工具 `tools/video_to_vseq.py` 默认可生成 YUV444；现有 `vseq_reader` + `vseq_yuv_unpack` + `color_space` 均已 `[U]`，但完整视频播放链还没有 `[C]`。

建议 P3 先做 YUV444 低分辨率短片，避免在 P1/P2 之前同时引入 SD 带宽、YUV420 去交错和复杂帧调度。

## 5. 明确不承诺的能力

这些不是“失败项”，而是主动缩小范围以保证比赛工程稳定：

- **不做实时 H.264/HEVC/MP4 解码**；答辩称“短视频片段 / 原始帧序列播放”。
- **暂不承诺 1080p**；1280×720 是正式性能目标，但尚未取得板级 timing closure。1080p60 只做 compile-time/TD 可行性探索，必须先证明 148.5/742.5 MHz pixel/serial 时钟及 EG PHY 时序。
- 不做 GPU 风格窗口系统、任意透明混合、抗锯齿 UI、完整频谱 FFT。
- 不为追求功能数量修改已冻结 P0 契约。
- 不猜 vendor primitive、PLL、APUG011/APUG092 端口、HDMI 差分 pin 或 IOSTANDARD。
- 单板基线稳定前，不把多 FPGA 扩展当成主线依赖。


## 5.1 当前 P1-04A 真板时钟候选边界

P1-04A 的 50->75/375MHz 720p 色条实验已经证明 synthesis 可行但 STA 未闭合，因此不再作为首次 board bring-up。P1-04B 改为复现用户 working official lab_ex4_tf：50MHz 输入、25/125MHz HDMI clocks、640×480、真实 HDMI_B pins。P1-03B/P1-04A 继续作为 720p transport/clock stress profile。

P1-04A 仍不是可烧录 build：当前上传物中没有用户今日实测通过的 `lab_ex4_tf` 板级 ADC，因此 package pin/IOSTANDARD 不猜测；同时 `p1_hdmi_pll_50m_75_375.ipc` 需要在 TD5.6.2 IP Generator 中生成一次，以核对 EG PLL 的 analog tuning 与 phase fields。P1-04B 完成真实 ADC 导入和 PLL 生成比对后，才进入 `[S]`/`[B]`。用户报告官方样例 KEY1/KEY2 可能互换，首次 smoke top 因而不使用按键复位。

## 6. 质量目标

项目“完成”必须由证据驱动，而不是由代码存在驱动：

- 模块级：有自检 TB 并达到 `[U]`；
- 子链/整链：多模块真实握手组合达到 `[C-sub]` / `[C]`；
- 工具链：TD synthesis/P&R 通过，timing/resource/RAM inference/clock constraints 人工检查后才 `[S]`；
- 真板：真实 SDRAM、TF、HDMI、音频和交互完成后才 `[B]`；
- 稳定性：连续运行至少 2h，并反复切换媒体无掉线/花屏/撕裂后才 `[L]`。

最终演示的功能最低成功线为：**分辨率不低于官方样例（640×480）且 HDMI 稳定出图 + 真 TF 图片播放 + 无撕裂切换 + HDMI 音频/提示音 + 交互/应急模式 + TD/资源/时序证据完整**。性能目标仍是单板 1280×720；只有 TD timing + 真板稳定通过后才把 720p 写成已达成。

## 7. PC 工具目标

现有工具继续作为“内容制备工具”而非运行时计算：

- `video_to_vseq.py`：原始帧序列打包/回读校验；
- `make_sd_card.py`：生成最小 FAT32 测试镜像；
- `gen_font.py`：生成 8×16 OSD 字模。

工具输出必须可被 RTL testbench 或真板读取验证，不能只“生成成功”就视为系统功能完成。


当前板级 HDMI 基线已完成：P1-04C 在 HX4S20C HDMI_B 实测输出 640×480 彩条。后续功能开发基于该硬件闭环继续扩展。
