# 11 · AI Agent 任务计划书（项目框架 + 实现流程）

> 面向对象：Codex / DeepSeek 等 AI 编码 agent；人类负责**架构审核、仿真通过、上板联调**。
> 用法：按本计划的**任务卡**逐模块实现；每个模块=一个 PR；仿真 `PASS` 才能提交。

## 0. 一句话

基于安路 HX4S20C（EG4S20BG256，19600 LUT）做“信息发布与应急广播终端”：SD/TF 读媒体 → SDRAM 帧缓存 → 图像视频处理（YCbCr→RGB、缩放、增强、OSD、转场）→ TMDS 编码 → HDMI 显示 + 音频，**全程无外部 CPU**。

**红线**：① 不用外部处理器；② 厂商 IP（PLL/SDRAM/HDMI 串行化）**由人在 TD GUI 例化并核对**，AI 只写 RTL 与约束，不凭空造 IP 端口；③ 每个模块必须带 testbench，ModelSim 输出 `PASS`。

> 进度口径(T3 之后): 全部**纯 RTL 模块**已实现并通过仿真(21 个 testbench PASS);
> 尚未交付: `top.v` 整合、`clk_gen`(PLL)、`sdram_ctrl`/`frame_buffer`(厂商 IP/参考)、
> `tmds_encoder`、`hdmi_audio`(官方参考)——这些需人工核对官方样本后集成或上板验证。

---

## 1. 模块地图（√=已完成）

### src/（可综合 RTL，按子系统）
| 子系统 | 模块 | 状态 | 依赖 | 厂商IP? |
|---|---|---|---|---|
| top | `top.v` / `clk_gen.v` / `reset_gen.v` √ | reset_gen 完成 | 全部 | clk_gen 用 PLL |
| storage | `sd_spi.v` √ / `sd_reader.v` √ / `fat32_scan.v` √ / `bmp_parser.v` √ / `vseq_reader.v` √ | 全部纯RTL完成 | async_fifo | SD 参考 |
| framebuf | `sdram_ctrl.v` / `frame_buffer.v` / `async_fifo.v` √ | async_fifo 完成 | async_fifo 独立 | SDRAM 用厂商 IP |
| display | `vga_timing.v` √ / `image_enhance.v` √ / `color_space.v` √ / `image_scaler.v` √ / `transition.v` √ / `osd_overlay.v` √ / `tmds_encoder.v` | 大部分 | valid 握手 | TMDS 用官方参考 |
| audio | `hdmi_audio.v` / `tone_gen.v` √ | 部分(纯RTL部分完成) | — | 官方参考 |
| interact | `key_filter.v` √ / `sw_filter.v` √ / `menu_fsm.v` √ / `seg_driver.v` √ / `dual_led.v` √ / `beep.v` √ | 全部完成 | — | 纯 RTL |
| app | `app_scenario.v` √ | 完成 | menu/display | 纯 RTL |

### sim_tb/（testbench，按 src 分目录）
`sim_tb/<subsystem>/tb_<模块>.v` + `run_<模块>.do`，与 src/ 一一对应。

### 运行
ModelSim 在 `sim_work/` 目录执行：
```powershell
cd sim_work
vsim -c -do ../sim_tb/display/run_image_enhance.do
```

---

## 2. 全局约定（Agent 必须遵守）

1. 一模块一文件，**文件名=模块名**；位置按 `src/<子系统>/`。
2. 端口用**握手约定**：数据带 `*_valid`（数据有效），跨时钟域一律用 `async_fifo`；**禁止**用快时钟直接采样慢时钟信号。
3. 顶部写 IEEE 风格头注释：作者 / 日期 / 版本 / 功能 / 端口说明 / 时钟域 / 修改历史。
4. 纯 RTL 尽量可综合；涉及厂商原语时只写**调用位置+注释**，不编端口名，由人核对官方 lab_ex。
5. 每个模块交付 = `src/.../xxx.v` + `sim_tb/<sub>/tb_xxx.v` + `sim_tb/<sub>/run_xxx.do`（+ 必要说明）。
6. 仿真必须 `PASS`；`$display("PASS: ...")` 作为验收标志。
7. 不改动已 `√` 模块的对外端口；如需改，先同步文档与相关 tb。

---

## 3. 依赖与实现顺序

```
地基(纯RTL, 可先做):
  T2 vga_timing √ → T3 async_fifo → T12 image_enhance √
  → T17 key_filter → T18 sw_filter → T20 seg_driver → T21 dual_led → T22 beep

数据通路(storage/framebuf):
  T4 sd_spi → T5 fat32_scan → T6 bmp_parser → T7 vseq_reader
  T8 sdram_ctrl(厂商IP) → T9 frame_buffer(双/三缓冲)

显示处理(display):
  T10 color_space(YCbCr→RGB) → T11 image_scaler → T13 transition → T14 osd_overlay

输出/音频:
  T15 tmds_encoder(官方参考) → T16 hdmi_audio / tone_gen

应用/集成:
  T19 menu_fsm → T23 app_scenario → T1 clk_gen(PLL) → T0 top 整合
```
**优先级**：先地基纯 RTL（可立即仿真），再数据通路，再显示，最后 `top` 集成。厂商 IP 相关的留给人。

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

| 里程碑 | 内容 | 交付物 | 验收 |
|---|---|---|---|
| M1 地基 | vga_timing√、image_enhance√、async_fifo、key_filter、seg_driver | 各模块 RTL+tb | 各自仿真 PASS |
| M2 数据通路 | sd_spi、fat32_scan、bmp_parser、vseq_reader | 读图/读帧→SDRAM | 仿真读文件序列正确 |
| M3 帧缓存 | sdram_ctrl(IP)、frame_buffer(双/三缓冲) | 缓存读写/无撕裂 | 仿真 + 上板 |
| M4 显示处理 | color_space、image_scaler、osd_overlay、transition | 处理流水线 | 仿真输出符合预期 |
| M5 输出/音频 | tmds_encoder(官方)、hdmi_audio、tone_gen | 显示+音频 | 上板 HDMI 出图+音 |
| M6 交互/应用 | menu_fsm、sw_filter、dual_led、beep、app_scenario | 完整交互 | 按键/拨码生效 |
| M7 集成 top | clk_gen(PLL)、top.v | 完整设计 | 上板稳定运行≥2h |

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
- 集成测试：需要时建 `tb_top` 例化多个模块（如 vga_timing + 彩条 + image_enhance）验证**模块连接/接口匹配**。

---

## 7. 集成路径（从模块到 top）

1. **mini-top**：`vga_timing` + 测试彩条源 + `image_enhance` → 输出带时基的图（验证接口）。
2. 加 `color_space`（接视频源）；加 `osd_overlay`（字幕/时间戳）。
3. 加 `frame_buffer`（图片/视频双/三缓冲）。
4. 加 `tmds_encoder` + `hdmi_audio` → 上板出图出声。
5. 建 `src/top/top.v` 例化全部，设为 TD 的 TOP，加 `constraints/`。

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
