# 11 · AI Agent 任务计划书（项目框架 + 实现流程）

> 面向对象：Codex / DeepSeek 等 AI 编码 agent；人类负责**架构审核、仿真通过、上板联调**。
> 用法：按本计划的**任务卡**逐模块实现；每个模块=一个 PR；仿真 `PASS` 才能提交。

## 0. 一句话

基于安路 HX4S20C（EG4S20BG256，19600 LUT）做“信息发布与应急广播终端”：SD/TF 读媒体 → SDRAM 帧缓存 → 图像视频处理（YCbCr→RGB、缩放、增强、OSD、转场）→ TMDS 编码 → HDMI 显示 + 音频，**全程无外部 CPU**。

**红线**：① 不用外部处理器；② 厂商 IP（PLL/SDRAM/HDMI 串行化）**由人在 TD GUI 例化并核对**，AI 只写 RTL 与约束，不凭空造 IP 端口；③ 每个模块必须带 testbench，ModelSim 输出 `PASS`。

> 进度口径(2026-08-28): 已实现并通过仿真的纯 RTL/PC 工具共 27 个 testbench PASS（✅）；
> A 组除可选 SDIO 4-bit 外已全部完成（✅）；B/C 组仍需人工拿到官方 lab_ex 与板卡约束。
> 剩余工作按可做性分为 A(Codex 可继续)/B(需厂商 IP)/C(需上板) 三类，详见 **§1.5**。
> **B 组(供应商 IP：clk_gen PLL、sdram_ctrl、TMDS 串行化+差分、HDMI 注入时序)与 C 组(上板联调：frame_buffer、top、constraints、集成\稳定性、720p)必须等人工拿到官方 lab_ex 与板卡约束，Codex 不编引脚、不造 IP 端口。**

---

## 1. 模块地图（✅=已完成 / ❌=未完成）

### src/（可综合 RTL，按子系统）
| 子系统 | 模块 | 状态 | 依赖 | 厂商 IP / 上板说明 |
|---|---|---|---|---|
| top | `reset_gen.v` | ✅ | — | 纯 RTL，已仿真 |
| top | `clk_gen.v` | ❌ | PLL | **厂商 IP**：PLL 生成 clk_pix/clk_tmds/clk_sdram/clk_sdo/clk_aud；必须人工在 TD GUI 例化，AI 不编端口 |
| top | `top.v` | ❌ | 全部模块 | **需上板**：完整顶层、IO 路由、引脚约束；需官方板卡资料并人工集成 |
| storage | `sd_spi.v` | ✅ | — | 纯 RTL，SPI Mode0 字节控制器 |
| storage | `sd_reader.v` | ✅ | `sd_spi` | 纯 RTL，SD SPI 命令状态机 |
| storage | `fat32_scan.v` | ✅ | — | 纯 RTL，FAT32 根目录/文件索引 |
| storage | `bmp_parser.v` | ✅ | — | 纯 RTL，24 位非压缩 BMP |
| storage | `vseq_reader.v` | ✅ | — | 纯 RTL，`.vseq` 头+帧流解析 |
| storage | `vseq_yuv_unpack.v` | ✅ | `vseq_reader` | 纯 RTL，YUV444 字节流→逐像素 Y/Cb/Cr |
| storage | `sdio_4bit.v`（可选） | ❌ | SD 物理时序 | A 组可选纯 RTL，未实现；SDIO 4-bit 读卡需 SD 时序参考，若调不通退回 SPI |
| framebuf | `async_fifo.v` | ✅ | — | 纯 RTL，异步 FIFO |
| framebuf | `sdram_ctrl.v` | ❌ | SDRAM IP | **厂商 IP/官方参考**：命令/自动刷新/行预充电/仲裁；人工例化 |
| framebuf | `frame_buffer.v` | ❌ | `sdram_ctrl` | **需上板**：图片双缓冲/视频三缓冲，需先与人工锁定 SDRAM 读写接口契约 |
| display | `vga_timing.v` | ✅ | — | 纯 RTL，HS/VS/DE+像素坐标 |
| display | `color_space.v` | ✅ | `yuv420_upsample` | 纯 RTL，BT.601 YUV444→RGB |
| display | `yuv420_upsample.v` | ✅ | `color_space` | 纯 RTL，420→444 最近邻上采样，含坐标延迟输出 |
| display | `image_scaler.v` | ✅ | — | 纯 RTL，最近邻坐标映射 |
| display | `image_enhance.v` | ✅ | — | 纯 RTL，亮度/对比度 |
| display | `transition.v` | ✅ | — | 纯 RTL，淡入淡出/水平擦拭 |
| display | `osd_overlay.v` | ✅ | 字库 ROM | 纯 RTL，8×16 字模叠加 |
| display | `tmds_encoder.v`（10bit 编码逻辑） | ✅ | 显示链 | A 组纯逻辑，已完成；只做数据/控制/同步通道编码，不含串行化 |
| display | `tmds_serializer.v`（串行化+差分） | ❌ | `tmds_encoder` | **厂商 IP/官方参考**：OSERDES/差分 IO 原语；人工按官方 lab_ex 核对 |
| audio | `tone_gen.v` | ✅ | — | 纯 RTL，DDS 测试音 |
| audio | `audio_visual.v` | ✅ | `vga_timing` | 纯 RTL，振幅包络柱状图 |
| audio | `hdmi_audio_pack.v`（L-PCM/IEC60958 打包） | ✅ | `tone_gen`/PCM | A 组纯逻辑，已完成；不包含注入 TMDS 时序 |
| audio | `hdmi_audio_inject.v`（注入 TMDS） | ❌ | `hdmi_audio_pack` | **厂商 IP/官方参考+需上板**：Data Island 注入时序，人工核对 |
| interact | `key_filter.v` | ✅ | — | 纯 RTL，按键消抖/边沿 |
| interact | `sw_filter.v` | ✅ | — | 纯 RTL，拨码消抖 |
| interact | `menu_fsm.v` | ✅ | 交互事件 | 纯 RTL，主控状态机 |
| interact | `seg_driver.v` | ✅ | — | 纯 RTL，数码管扫描 |
| interact | `dual_led.v` | ✅ | — | 纯 RTL，双色 LED |
| interact | `beep.v` | ✅ | — | 纯 RTL，蜂鸣器 |
| app | `app_scenario.v` | ✅ | menu/display | 纯 RTL，信息发布/应急广播 FSM |

### sim_tb/（testbench，按 src 分目录）
`sim_tb/<subsystem>/tb_<模块>.v` + `run_<模块>.do`，与 src/ 一一对应。

### 运行
ModelSim 在 `sim_work/` 目录执行：
```powershell
cd sim_work
vsim -c -do ../sim_tb/display/run_image_enhance.do
```

---

## 1.5 模块可做性分级（谁来做 / 要不要上板）

> 依据 `docs/02_architecture.md` 与红线：**厂商 IP（PLL/SDRAM/TMDS 串行化/HDMI 时序）由人在 TD GUI 例化并核对；AI 不编端口、不造 IP**。
> 凡属“纯 RTL / PC 脚本”且无需厂商原语的，Codex 可继续（ModelSim 或脚本自检）；凡涉厂商原语或物理 IO/时序的，需人工或上板。

### A) 仍可交给 Codex（纯 RTL 或 PC 工具，无需开发板）
| 模块 | 子系统 | 说明/注意 |
|---|---|---|
| `yuv420_upsample` | display | ✅ 420→444 色度上采样（最近邻，行缓冲 2×2 复制），color_space 前置，已含坐标延迟输出 |
| YUV444 字节流解包 | storage | ✅ `vseq_yuv_unpack` 已完成；配合 `video_to_vseq.py --format yuv444` 使用 |
| TMDS 10bit 编码器（数据/控制/同步通道 + XOR/XOR + DC 平衡） | display | ✅ 纯逻辑编码器已完成；**串行化/差分输出**部分留给人工（官方 lab_ex） |
| HDMI 音频包生成（L-PCM 样本 + IEC60958 子帧打包 + 偶校验） | audio | ✅ 纯逻辑打包已完成；**注入 TMDS 通道时序**由人工/上板核对 |
| mini-top 显示链集成仿真（vga_timing+彩条+color_space+image_enhance+transition+osd_overlay） | top/display | ✅ 已完成(3 帧逐像素/OSD/参考色全对齐) |
| 音频可视化（扩展⑤：振幅条/简易频谱） | audio/display | ✅ 已完成(包络柱状图 audio_visual, 低资源，柱高已按满幅映射修正) |
| PC 工具：`video_to_vseq.py`、`make_sd_card.py`、`gen_font.py`(+OSD 字模数据) | tools | ✅ `video_to_vseq.py` 默认 YUV444 直连 `vseq_yuv_unpack`，并可选 planar YUV420/RGB；`make_sd_card.py` 已生成最小 FAT32 镜像；`gen_font.py` 已生成 8x16 字模 HEX |
| （可选）SDIO 4-bit 读卡 | storage | ❌ 纯 RTL 但复杂度高、需 SD 时序参考；两周调不通退回 SPI+预载循环 |

### B) 需厂商 IP 核（人在 TD GUI 例化；AI 只写“调用占位+接口注释”）
| 模块 | 说明 |
|---|---|
| ❌ `clk_gen` | PLL 生成 clk_pix/clk_tmds/clk_sdram/clk_sdo/clk_aud；必须人工例化 PLL |
| ❌ `sdram_ctrl` | SDRAM 控制器（命令/自动刷新/行预充电/仲裁）；复用官方 IP/参考 |
| ❌ `tmds_encoder` 串行化 + 差分 IO | OSERDES/原语，按官方 lab_ex 参考，Codex 不改参考接口 |
| ❌ `hdmi_audio` 注入 TMDS 通道 | Data Island 注入时序按官方参考 |

### C) 需开发板/上板联调（引脚、物理时序、资源与稳定性收敛）
| 模块/任务 | 说明 |
|---|---|
| ❌ `frame_buffer`（双/三缓冲） | **需先与人工锁定 sdram 读/写接口契约**；纯逻辑 Codex 可写，但真写读、无撕裂须上板验证 |
| ❌ `top.v` 完整顶层 | 例化全部 + IO 路由 + 引脚约束（引脚号见官方资料） |
| ❌ `constraints/*.cst/*.sdc` | **必须来自官方板卡资料**，禁止 AI 编引脚号；由人核对后转写 |
| ❌ 系统集成联调 | HDMI 出图、音频出声、长稳 ≥2h、反复快速切图无花屏/撕裂 |
| ❌ 720p 扩展验证 | TMDS 位时钟 ~742MHz 逻辑串行化极限实测（加分项，不承诺） |

> 节奏建议：先把 A 组（尤其 mini-top 集成 + TMDS 编码器 + HDMI 音频包）用仿真跑通，
> 再等人工拿到官方 lab_ex 与板卡约束，进入 B/C 组；AI 在 B 组只产出“端口契约+占位”，不交付可综合 RTL。
>
> **后续 UI**：显示器界面按“分层叠加”设计，详见 `docs/12_ui_overlay_design.md`（理论分析，暂不实现）；
> 落地为 A 组纯 RTL（状态栏/时间、滚动标语、参数面板、音频柱、应急整屏、优先级 mux），每步独立仿真。

---

## 2. 全局约定（Agent 必须遵守）

1. 一模块一文件，**文件名=模块名**；位置按 `src/<子系统>/`。
2. 端口用**握手约定**：数据带 `*_valid`（数据有效），跨时钟域一律用 `async_fifo`；**禁止**用快时钟直接采样慢时钟信号。
3. 顶部写 IEEE 风格头注释：作者 / 日期 / 版本 / 功能 / 端口说明 / 时钟域 / 修改历史。
4. 纯 RTL 尽量可综合；涉及厂商原语时只写**调用位置+注释**，不编端口名，由人核对官方 lab_ex。
5. 每个模块交付 = `src/.../xxx.v` + `sim_tb/<sub>/tb_xxx.v` + `sim_tb/<sub>/run_xxx.do`（+ 必要说明）。
6. 仿真必须 `PASS`；`$display("PASS: ...")` 作为验收标志。
7. 不改动已 `✅` 模块的对外端口；如需改，先同步文档与相关 tb。

---

## 3. 依赖与实现顺序

```
地基(纯RTL, 已全部完成):
  T2 vga_timing ✅ → T3 async_fifo ✅ → T12 image_enhance ✅
  → T17 key_filter ✅ → T18 sw_filter ✅ → T20 seg_driver ✅ → T21 dual_led ✅ → T22 beep ✅
  → T1 reset_gen ✅

数据通路(storage 已完成; framebuf 待厂商 IP/上板):
  T4 sd_spi ✅ → T5 fat32_scan ✅ → T6 bmp_parser ✅ → T7 vseq_reader ✅ → T10 sd_reader ✅(读块)
  T8 sdram_ctrl ❌[B 厂商IP] → T9 frame_buffer ❌[C 上板, 且需先锁 sdram 写读契约]

显示处理(display 纯逻辑已完成; TMDS 编码器纯逻辑完成):
  T10 color_space ✅(YUV444) → yuv420_upsample ✅ → T11 image_scaler ✅
  → T13 transition ✅ → T14 osd_overlay ✅ → T15a TMDS 10bit 编码器 ✅[A]

输出/音频(纯 RTL 编码/打包完成; 注入/串行化待厂商参考):
  T15b tmds 串行化/差分 ❌[B+官方参考] → T16a hdmi 音频包生成 ✅[A] → T16b 注入 TMDS 时序 ❌[B+官方参考]
  → tone_gen ✅ → audio_visual ✅

应用/集成(应用与 mini-top 完成; PLL/top 待人工):
  T19 menu_fsm ✅ → T23 app_scenario ✅ → T1 clk_gen ❌[B 厂商IP] → T0 top 整合 ❌[C 上板]
  → mini-top 显示链集成仿真 ✅[A]
```
**优先级**：先完成 A 组（含 mini-top 集成、TMDS 编码器、HDMI 音频包、yuv420 上采样、PC 工具、音频可视化）；
厂商 IP 相关的 B 组、需要上板的 C 组留给人，等官方 lab_ex 与板卡约束到位后再做。

---

## 4. 任务卡模板

```
模块: <名称> (<子系统>)
文件: src/<子系统>/<name>.v
端口: <clock / rst_n / 输入 / 输出 / 参数>
功能: <做什么，公式/状态机/时序>
测试: sim_tb/<子系统>/tb_<name>.v 激励与判定
验收: ModelSim 输出 PASS；给出主动校验的关键值
依赖: <引用的子模块/跨时钟域>
厂商IP: <无 / 有，需人工>
```

### 示例卡 1：async_fifo（T3，framebuf）
- 端口：`wr_clk/wr_rst_n/wr_en/din[]`、`rd_clk/rd_rst_n/rd_en`、`dout[]/full/empty`；参数 `DATA_WIDTH`、`ADDR_WIDTH`（深度=2^n）。
- 功能：双时钟异步 FIFO，用**格雷码指针**跨时钟域；`full`/`empty` 由同步后的对侧指针判断；memory 用数组。
- 测试：写/读两个独立时钟；写入序列、按序读出并比对；验证满/空标志；输出 `PASS`。
- 注意：禁止用 bin 指针直接跨域；格雷码在两端各自打拍。

### 示例卡 2：color_space（T10，display，YCbCr→RGB）
- 端口：`clk / rst_n / pixel_valid / y,cb,cr[7:0]` → `pixel_valid_out / r,g,b[7:0]`；`valid` 握手（兼容 vga_timing）。
- 功能：BT.601 定点矩阵 `R=Y+1.402(Cr-128)` 等；YUV420 需先色度上采样（最近邻/双线性）。
- 测试：喂已知 Y/Cb/Cr，核对 RGB（手算一组），`PASS`。
- 注意：彩色差值用定点（移位/乘法器），避免浮点。

### 示例卡 3：key_filter（T17，interact）
- 端口：`clk / rst_n / key_in[3:0]` → `key_out[3:0]`，参数 `CNT_MAX`（消抖时钟数）。
- 功能：按键消抖 + 边沿检测（长按可选）；输出稳定后的有效键值。
- 测试：给带抖动的按键，输出稳定的 `key_out`，`PASS`。

---

## 5. 实现流程（里程碑）

| 里程碑 | 内容 | 交付物 | 验收 | 状态 |
|---|---|---|---|---|
| M1 地基 | vga_timing ✅、image_enhance ✅、async_fifo ✅、key_filter ✅、sw_filter ✅、seg_driver ✅、dual_led ✅、beep ✅、reset_gen ✅ | 各模块 RTL+tb | 各自仿真 PASS | ✅ 完成 |
| M2 数据通路 | sd_spi、fat32_scan、bmp_parser、vseq_reader、sd_reader | 读图/读帧 | 仿真读文件序列正确 | ✅ 完成(纯逻辑) |
| M4 显示处理 | color_space、image_scaler、transition、osd_overlay | 处理流水线 | 仿真输出符合预期 | ✅ 完成(纯逻辑) |
| M6 交互/应用 | menu_fsm、sw_filter、dual_led、beep、app_scenario | 完整交互 | 按键/拨码生效 | ✅ 完成(纯逻辑) |
| M2.5 数据通路增强[A] | yuv420_upsample、(可选)SDIO 4-bit | 上采样/高带宽 | 仿真正确 | 部分：yuv420_upsample ✅；SDIO ❌ |
| M4.5 显示扩展[A] | TMDS 10bit 编码器、mini-top 显示链集成、音频可视化 | 编码器+互联 tb | 仿真验证接口 | mini-top ✅、audio_visual ✅、TMDS 10bit ✅ |
| M5 输出/音频 | tmds 串行化(官方)、hdmi_audio 注入(官方)、tone_gen、hdmi_audio_pack | HDMI 出图+音 | 上板出图出声 | 部分：tone_gen ✅、hdmi_audio_pack ✅；tmds/hdmi 注入 ❌(厂商) |
| M3 帧缓存 | sdram_ctrl(B厂商IP)、frame_buffer(C上板) | 缓存读写/无撕裂 | 仿真 + 上板 | ❌ 待人工 IP + 锁契约 |
| M7 集成 top | clk_gen(B厂商IP)、top.v(C上板)、constraints(C官方资料) | 完整设计 | 上板稳定≥2h | ❌ 待人工 |

---

## 6. 仿真验证（每个模块）

- 在 `sim_tb/<子系统>/tb_<模块>.v` 写**激励 + 自检**（`$error` 计数，结尾 `$display("PASS/FAIL")`）。
- 编译需带上被测模块**及其例化的子模块** .v；在 `sim_work` 下：
  ```powershell
  cd sim_work
  vlib work
  vsim -c -do ../sim_tb/<子目录>/run_<模块>.do
  ```
- `run_<模块>.do` 固定为：`vlib work; vlog <dut.v> <tb.v>; vsim <tb>; run -all; quit -f`。
- 集成测试：需要时建 `tb_mini_top` 例化多个模块（如 vga_timing + 彩条 + image_enhance）验证**模块连接/接口匹配**。

---

## 7. 集成路径（从模块到 top）

1. **mini-top（Codex 可做，纯仿真）**：`vga_timing` + 测试彩条源 + `image_enhance` → 输出带时基的图（验证接口）。
2. 加 `color_space`（接视频源）；加 `image_scaler`/`transition`；加 `osd_overlay`（字幕/时间戳）→ **Codex 可做**（纯显示链联调）。
3. 加 `frame_buffer`（图片/视频双/三缓冲）→ **需 sdram 接口契约 + 上板验证**。
4. 加 `tmds_encoder`(串行化) + `hdmi_audio`(注入) → **需官方参考 + 上板**（出图出声）。
5. 建 `src/top/top.v` 例化全部，设为 TD 的 TOP，加 `constraints/`（**需官方板卡资料，人工**）。

---

## 8. 协作与 PR

- 每个模块一个 PR；提交信息 `type(scope): subject`。
- 流程：1 人开发（pull main→分支→改→PASS→push→PR）→ 2 人审查（可拉分支本地测）→ 均为 Approve → Squash and merge。
- 厂商 IP 模块在 PR 描述标注“**已留注释，需人工 TD 例化核对**”。

---

## 9. 验收总表（对齐评分）

| 评分项 | 覆盖模块 | 目标 |
|---|---|---|
| 基础①核心功能 | sd_spi/fat32/bmp/vseq/frame_buffer/tmds | 读+显示+切图/轮播 |
| 基础②显示稳定 | frame_buffer/vga_timing/tmds | ≥2h、无花屏撕裂 |
| 基础③基础音频 | hdmi_audio/tone_gen | HDMI 出声 |
| 基础④工程规范 | 全部 | 模块化/注释/约束/文档 |
| 扩展①字幕图层 | osd_overlay | 时间戳+滚动标语 |
| 扩展②转场 | transition | 淡入淡出/滑动 |
| 扩展③缩放 | color_space/image_scaler | 多分辨率适配 |
| 扩展④实时调节+OSD | image_enhance/menu_fsm | 亮度/对比度+参数显示 |
| 扩展⑤音频可视化 | tone_gen/可视化 | 频谱/波形叠加 |
