# 11 · AI Agent 任务计划书（项目框架 + 实现流程）

> 面向对象：Codex / DeepSeek 等 AI 编码 agent；人类负责**架构审核、仿真通过、上板联调**。
> 用法：按本计划的**任务卡**逐模块实现；每个模块=一个 PR；仿真 `PASS` 才能提交。

## 0. 一句话

基于安路 HX4S20C（EG4S20BG256，19600 LUT）做“信息发布与应急广播终端”：SD/TF 读媒体 → SDRAM 帧缓存 → 图像视频处理（YCbCr→RGB、缩放、增强、OSD、转场）→ TMDS 编码 → HDMI 显示 + 音频，**全程无外部 CPU**。

**红线**：① 不用外部处理器；② 厂商 IP（PLL/SDRAM/HDMI 串行化）**由人在 TD GUI 例化并核对**，AI 负责业务 RTL、wrapper/adapter 与 testbench；约束文件只能依据官方原理图/官方工程转写，由人工核对，禁止 AI 猜测引脚、IOSTANDARD、时钟约束或 vendor IP 端口；③ 每个模块必须带 testbench，ModelSim 输出 `PASS`。

> 进度口径(2026-08-31): **36 个 `tb_*.v` 全部 ModelSim PASS**；P0-01~P0-07 `[U]`，P0-08 framebuffer/mock `[C-sub]`，P0-09 完整媒体主链 **`[C] CHAIN PASS`**。P0 Implementation Freeze v1.0 已生效。
> P0-05 `line_buffer_pingpong` 修复 TB golden 位宽后 CASE-GOLDEN+CASE0~CASE8 PASS（checks=2204）；P0-06 `line_prefetcher` CASE0~CASE13 PASS（checks=2713）。
> P0-07 `sdram_arbiter` `[U]`（checks=39）；P0-08 framebuffer/mock `[C-sub]`（checks=1495）；P0-09 end-to-end `[C]`（checks=1698）。
> 官方 HDMI 使用 APUG092，官方 SDRAM 使用 APUG011；不再以自研 TMDS/SDRAM 作为正式比赛主链。
> P0 已冻结；P1 从 APUG011/APUG092 adapter/vendor/TD 集成开始。planar YUV420、SDIO 4-bit 仍属后续扩展，不得阻塞 P1。
> 剩余工作按可做性分为 A(Codex 可继续)/B(需厂商 IP)/C(需上板) 三类，详见 **§1.5**。
> **B 组(供应商 IP 与 TD 集成：PLL、APUG011、APUG092、system\_top/hx4s20c\_top、constraints、TD synthesis/P\&R)依赖 vendor/TD，但不依赖开发板。
> C 组只保留真实硬件验证：真卡读取、HDMI 物理输出、长稳/切图压力、720p。**

***

## 0.1 Architecture Freeze v1.0 — 2026-08-31

自本版本起，AI Agent 不得因实现方便、局部优化或新的个人建议自行改变主数据流、模块边界、vendor IP 选择、SDRAM 像素格式及时钟架构。

仅当安路官方资料、TD 综合/P\&R/时序结果或真实开发板测试证明当前契约存在冲突时，才能提出 Architecture Change Request。

变更流程：

1. 先修改架构文档；
2. 经人工审核通过；
3. 再修改 RTL。

***

## 1. 模块地图

状态标记：

```text
[U] UNIT PASS
[C] CHAIN PASS
[S] TD SYNTH/P&R PASS，且 timing/resource/RAM inference/clock constraints 检查通过
[B] BOARD PASS
[L] LONG-RUN PASS
❌  未完成
```

### src/（可综合 RTL，按子系统）

| 子系统      | 模块                                     | 状态   | 依赖                                     | 厂商 IP / 上板说明                                                                                                          |
| -------- | -------------------------------------- | ---- | -------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| top      | `reset_gen.v`                          | \[U] | —                                      | 纯 RTL，已仿真                                                                                                             |
| top      | `clk_gen.v`                            | ❌    | PLL                                    | **厂商 IP**：PLL 生成 clk\_pix、clk\_hdmi\_ser=clk\_pix×5、clk\_sdram、clk\_sdo；必须人工在 TD GUI 例化                               |
| top      | `hx4s20c_top.v`                        | ❌    | 全部模块                                   | 板级 top：PLL、APUG011、APUG092、SD/HDMI physical IO、board reset、vendor primitive；**配合独立** **`constraints/`** **文件完成板级约束。** |
| storage  | `sd_spi.v`                             | \[U] | —                                      | 纯 RTL，SPI Mode0 字节控制器                                                                                                 |
| storage  | `sd_reader.v`                          | \[U] | `sd_spi`                               | 纯 RTL，SDHC/SDXC SPI 初始化+CMD17；单元 PASS，真卡仍需板级联调                                                                        |
| storage  | `fat32_scan.v`                         | \[U] | —                                      | 纯 RTL，FAT32 根目录索引；只读第一扇区，FAT chain/文件流另建模块                                                                            |
| storage  | `fat32_file_reader.v`                  | \[U] | `fat32_scan`                           | P0-01 已完成：cluster→LBA、fragmented FAT chain、连续文件字节流、`file_size` 截止；CASE0~CASE8 adversarial PASS（checks=18） |
| storage  | `bmp_parser.v`                         | \[U] | —                                      | 纯 RTL，24 位非压缩 BMP 头解析（含 start/done/字段校验）                                                                              |
| storage  | `bmp_pixel_stream.v`                   | \[U] | `bmp_parser`                           | P0-02 已完成：BGR→RGB、bottom-up、padding 0/1/2/3、x/y/pixel_valid；CASE0~CASE13 PASS（checks=13393） |
| storage  | `vseq_reader.v`                        | \[U] | —                                      | 纯 RTL，`.vseq` 头+帧流解析                                                                                                  |
| storage  | `vseq_yuv_unpack.v`                    | \[U] | `vseq_reader`                          | 纯 RTL，YUV444 字节流→逐像素 Y/Cb/Cr                                                                                          |
| storage  | `sdio_4bit.v`（可选）                      | ❌    | SD 物理时序                                | A 组可选纯 RTL，未实现；SDIO 4-bit 读卡需 SD 时序参考，若调不通退回 SPI                                                                      |
| framebuf | `async_fifo.v`                         | \[U] | —                                      | 纯 RTL，异步 FIFO（已改为注册 Gray 指针 + 2FF）                                                                                    |
| framebuf | `framebuffer_writer.v`                 | [U]   | `bmp_pixel_stream`                     | **P0-03 [U]**：CASE0~CASE8 PASS（checks=1345）；RGB/x/y→21-bit word address + `0x00RRGGBB` |
| framebuf | `frame_buffer_manager.v`               | [U]   | `framebuffer_writer`/`line_prefetcher` | **P0-04 [U]**：CASE0~CASE6 PASS（checks=166）；Image A/B 双缓冲、frame metadata、frame-boundary swap、读写保护 |
| framebuf | `line_prefetcher.v`                    | [U]   | `frame_buffer_manager`                 | **P0-06 [U]**：CASE0~CASE13 PASS（checks=2713）；连续行读、多 outstanding、有序 response/stale-response quarantine |
| framebuf | `sdram_arbiter.v`                      | [U] | writer + prefetcher                  | **P0-07 [U]**：strict read-priority、read/write 互斥、outstanding response guard；CASE0~CASE8 PASS（checks=39） |
| framebuf | `sdram_adapter.v`                      | ❌    | APUG011                                | 适配官方 `sdr_as_ram` 接口                                                                                                  |
| framebuf | `line_buffer_pingpong.v`               | [U]   | `line_prefetcher`                      | **P0-05 [U]**：CASE-GOLDEN+CASE0~CASE8 PASS（checks=2204）；双行 ping-pong、连续 active line、RGB 保真 |
| display  | `vga_timing.v`                         | \[U] | —                                      | 纯 RTL，APUG092 架构下作为内部 timing/x-y scheduler；由 `hdmi_video_adapter` 转官方 Video Interface                                 |
| display  | `color_space.v`                        | \[U] | `vseq_yuv_unpack`/`yuv420_upsample`    | 纯 RTL，BT.601 limited-range YUV444→RGB                                                                                 |
| display  | `yuv420_upsample.v`                    | \[U] | `color_space`                          | 纯 RTL，块色度流 420→444；标准 planar YUV420 仍需去交错                                                                             |
| display  | `image_scaler.v`                       | \[U] | —                                      | 纯 RTL，最近邻坐标映射                                                                                                         |
| display  | `image_enhance.v`                      | \[U] | —                                      | 纯 RTL，亮度/对比度                                                                                                          |
| display  | `transition.v`                         | \[U] | —                                      | 纯 RTL，淡入淡出/水平擦拭                                                                                                       |
| display  | `osd_overlay.v`                        | \[U] | 字库 ROM                                 | 纯 RTL，8×16 字模叠加                                                                                                       |
| display  | `tmds_encoder.v`（10bit 编码逻辑）           | \[U] | 显示链                                    | educational/reference RTL；正式主链使用 APUG092，不含串行化                                                                        |
| display  | `hdmi_video_adapter.v`                 | ❌    | APUG092                                | 项目 RGB888 像素流 → APUG092 Video Interface                                                                               |
| audio    | `tone_gen.v`                           | \[U] | —                                      | 纯 RTL，DDS 测试音                                                                                                         |
| audio    | `audio_visual.v`                       | \[U] | `vga_timing`                           | 纯 RTL，振幅包络柱状图                                                                                                         |
| audio    | `hdmi_audio_pack.v`（L-PCM/IEC60958 打包） | \[U] | `tone_gen`/PCM                         | educational/reference RTL；正式音频使用 APUG092                                                                              |
| audio    | `hdmi_audio_adapter.v`                 | ❌    | APUG092                                | pixel domain 下 24bit L/R → APUG092 Audio Interface                                                                    |
| interact | `key_filter.v`                         | \[U] | —                                      | 纯 RTL，2FF 同步 + 按键消抖/边沿                                                                                                |
| interact | `sw_filter.v`                          | \[U] | —                                      | 纯 RTL，2FF 同步 + 拨码消抖                                                                                                   |
| interact | `menu_fsm.v`                           | \[U] | 交互事件                                   | 纯 RTL，主控状态机                                                                                                           |
| interact | `seg_driver.v`                         | \[U] | —                                      | 纯 RTL，数码管扫描                                                                                                           |
| interact | `dual_led.v`                           | \[U] | —                                      | 纯 RTL，双色 LED                                                                                                          |
| interact | `beep.v`                               | \[U] | —                                      | 纯 RTL，蜂鸣器                                                                                                             |
| app      | `app_scenario.v`                       | \[U] | menu/display                           | 纯 RTL，信息发布/应急广播 FSM                                                                                                   |
| top      | `system_top.v`                         | ❌    | 全部业务逻辑                                 | 纯业务 top，不含 vendor primitive                                                                                           |

### sim\_tb/（testbench，按 src 分目录）

`sim_tb/<subsystem>/tb_<模块>.v` + `run_<模块>.do`，与 src/ 一一对应。

### 运行

ModelSim 在 `sim_work/` 目录执行：

```powershell
cd sim_work
vsim -c -do ../sim_tb/display/run_image_enhance.do
```

***

## 1.5 模块可做性分级（谁来做 / 要不要上板）

> 依据 `docs/02_architecture.md` 与红线：**厂商 IP（PLL/SDRAM/TMDS 串行化/HDMI 时序）由人在 TD GUI 例化并核对；AI 不编端口、不造 IP**。
> 凡属“纯 RTL / PC 脚本”且无需厂商原语的，Codex 可继续（ModelSim 或脚本自检）；凡涉厂商原语或物理 IO/时序的，需人工或上板。

### A) 仍可交给 Codex 的纯 RTL / PC 工具

完成状态使用 `[U]/[C]/[S]/[B]/[L]`，不再用单个 ✅ 表示系统完成。

| 模块/任务                  | 子系统           | 说明/状态                                                         |
| ---------------------- | ------------- | ------------------------------------------------------------- |
| `fat32_file_reader`    | storage       | \[U] fragmented FAT chain、cluster→LBA、`file_size` 终止；CASE0~CASE8 PASS（checks=18） |
| `bmp_pixel_stream`     | storage       | \[U] CASE0~CASE13 PASS（checks=13393）；BGR→RGB、bottom-up、padding、x/y/pixel_valid |
| `framebuffer_writer`   | framebuf      | [U] P0-03 CASE0~CASE8 PASS（checks=1345） |
| `frame_buffer_manager` | framebuf      | [U] P0-04 CASE0~CASE6 PASS（checks=166） |
| `line_prefetcher`      | framebuf      | [U] P0-06：CASE0~CASE13 PASS（checks=2713） |
| `sdram_arbiter`        | framebuf      | [U] P0-07：strict read-priority + response guard |
| `line_buffer_pingpong` | framebuf      | [U] P0-05：CASE-GOLDEN+CASE0~CASE8 PASS（checks=2204） |
| `hdmi_video_adapter`   | display       | ❌ 未实现：RGB888 → APUG092 Video Interface                        |
| `hdmi_audio_adapter`   | audio         | ❌ 未实现：pixel domain L/R → APUG092 Audio Interface              |
| `sdram_adapter`        | framebuf      | ❌ 未实现：适配 APUG011 `sdr_as_ram` 接口                              |
| YUV444 工具/解包           | storage/tools | \[U] `vseq_yuv_unpack`、`video_to_vseq.py --format yuv444` 已完成 |
| TMDS/IEC60958 教学 RTL   | display/audio | \[U] 保留 educational/reference，不进入正式 HDMI 主链                   |

### FAT32/BMP baseline

FAT32：

- 512-byte sector
- SDHC/SDXC
- 8.3 short filename
- 不依赖 LFN
- `fat32_scan` 当前只索引根目录第一 sector
- `fat32_file_reader` 必须支持 fragmented FAT chain
- 文件读出以 `file_size` 为最终边界，而不是仅靠 EOC

BMP：

- 24-bit
- BI\_RGB / uncompressed
- baseline 支持 bottom-up
- 必须处理 4-byte row padding

### P0-01 已交付记录：`fat32_file_reader`

- 状态：`[U] UNIT PASS`（2026-08-31）。
- 实测回归：CASE0~CASE8 全部 PASS，`checks=18`。
- 覆盖 fragmented chain、SPC=2、`file_size` 100/512/513/2050、premature EOC、free cluster、FAT offset=508、非法 SPC=0。
- 接口契约：`docs/13_fat32_file_reader_interface.md`。
- 测试向量：`docs/14_fat32_file_reader_test_vectors.md`。
- **不得因此将 storage/FAT32→BMP 主链标为 `[C]`。**

### B) 官方 vendor IP：AI 只读/解释/例化/wrapper

| vendor 来源                    | 用途                                                             | AI 权限                                                                              |
| ---------------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| APUG092 HDMI1.4b Transmitter | 正式 HDMI protocol、TMDS、Data Island、Audio、ACR、DDC/EDID           | 只读；写 `hdmi_video_adapter` / `hdmi_audio_adapter` / `hdmi_phy_wrapper(DEVICE="EG")` |
| APUG011 高性能 SDRAM            | 正式 SDRAM controller / `sdr_as_ram` / `EG_PHY_SDRAM_2M_32`      | 只读；写 `sdram_adapter`                                                               |
| PLL User Guide               | 生成 `clk_pix`、`clk_hdmi_ser=clk_pix×5`、SDRAM 时钟                 | 人工在 TD GUI 例化；AI 不编端口                                                              |
| IO User Guide                | 板级 IO / ODDR / 差分                                              | 人工核对；普通 `src/` 禁止出现 `EG_*` primitive                                               |
| `system_top.v`               | 纯业务 top，不包含 vendor primitive                                   | Codex 可写；不依赖开发板                                                                    |
| `hx4s20c_top.v`              | 板级 top：PLL、APUG011、APUG092、SD/HDMI PHY、board reset、constraints | 依赖 vendor/TD，不依赖开发板；人工核对例化                                                         |
| `constraints/*.cst/*.sdc`    | 必须来自官方板卡资料，人工核对                                                | 依赖官方资料；禁止 AI 编引脚                                                                   |
| 完整 TD synthesis/P\&R/timing  | `[S]`，需拿到 timing/resource/RAM inference/clock constraints 报告   | 依赖 TD；不依赖开发板                                                                       |

### C) 需开发板/上板联调

| 模块/任务       | 说明                           |
| ----------- | ---------------------------- |
| 上板稳定运行      | `[B]` 出图、`[L]` ≥2h           |
| SD 真卡读取验证   | `[B]` 真 TF 卡初始化/读块/连续多 block |
| HDMI 物理输出验证 | `[B]` APUG092 输出到显示器，无花屏/无掉线 |
| 长稳/切图压力测试   | `[L]` ≥2h、反复快速切图无撕裂          |

### 实现优先级

```text
P0: fat32_file_reader [U]
P0: bmp_pixel_stream [U]
P0: framebuffer_writer [U]
P0: frame_buffer_manager [U]
P0: line_buffer_pingpong [U]
P0: line_prefetcher [U]
P0: sdram_arbiter [[U]]

P0 主数据流：
  FAT32 image
    -> ...
    -> framebuffer_writer ─┐
                          ├→ sdram_arbiter → mock SDRAM
       line_prefetcher ───┘
                          ↓
                 line_buffer_pingpong
                          ↓
             display-order RGB stream
                          ↓
               Python golden compare

P0 验收：端到端 [C]

P1: sdram_adapter 对接 APUG011
P1: 官方 APUG011 simulation/synthesis
P1: hdmi_video_adapter + APUG092 EG wrapper
P1: hx4s20c board_top + ADC/SDC
P1: 完整 TD synthesis/P&R/timing

P2: 基础 HDMI audio
P2: OSD / transition / brightness / audio visual

P3: YUV444 短视频
P4: YUV420 / SDIO / 720p
```

在 P0/P1 完成以前，禁止新增其他展示特效。

***

## 2. 全局约定（Agent 必须遵守）

1. 一模块一文件，**文件名=模块名**；位置按 `src/<子系统>/`。
2. 端口用**握手约定**：数据带 `*_valid`（数据有效），跨时钟域一律用 `async_fifo`；**禁止**用快时钟直接采样慢时钟信号。
3. 顶部写 IEEE 风格头注释：作者 / 日期 / 版本 / 功能 / 端口说明 / 时钟域 / 修改历史。
4. 纯 RTL 尽量可综合；涉及 vendor 原语只允许在 `hx4s20c_top.v` 或 vendor wrapper 中例化，普通 `src/` 模块不得出现 `EG_PHY_*` / `EG_LOGIC_*`。
5. 每个模块交付 = `src/.../xxx.v` + `sim_tb/<sub>/tb_xxx.v` + `sim_tb/<sub>/run_xxx.do`（+ 必要说明）。
6. 仿真必须 `PASS`；`$display("PASS: ...")` 作为验收标志。
7. 不改动已达到 `[U]` 及以上状态模块的对外端口；如需改，先同步文档与相关 tb。

***

## 3. 依赖与实现顺序

```
地基纯 RTL（[U]）:
  vga_timing [U] → async_fifo [U] → image_enhance [U]
  → key_filter [U] → sw_filter [U] → seg_driver [U] → dual_led [U] → beep [U]
  → reset_gen [U]

媒体输入链（P0）:
  sd_spi [U] → sd_reader [U]
  → fat32_scan [U] → fat32_file_reader [U]
  → bmp_parser [U] → bmp_pixel_stream [U]
  → framebuffer_writer [U]

帧缓冲/显示（P0/P1）:
  frame_buffer_manager [U](控制)
    ├─ framebuffer_writer [U](写源) ─┐
    └─ line_prefetcher [U](P0-06 [U], 读源) ────┤
                                    ├→ sdram_arbiter [U] → mock SDRAM / APUG011
                                    ↓
                           line_buffer_pingpong [U]
                                    ↓
                       display-order RGB stream
                                    ↓
                         hdmi_video_adapter ❌ → APUG092

教育/展示 RTL（P2）:
  color_space [U] → yuv420_upsample [U] → image_scaler [U]
  → transition [U] → osd_overlay [U] → audio_visual [U]
  tmds_encoder [U]、hdmi_audio_pack [U]：educational/reference，不进入正式主链

板级集成（P1）:
  system_top ❌ → hx4s20c_top ❌ → constraints ❌ → TD synthesis/P&R ❌
```

**优先级**：先完成 P0 媒体输入与 framebuffer CHAIN，再进入 P1 官方 SDRAM/HDMI 适配；
P2 之前不得新增展示特效。

***

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

### 示例卡 1：async\_fifo（T3，framebuf）

- 端口：`wr_clk/wr_rst_n/wr_en/din[]`、`rd_clk/rd_rst_n/rd_en`、`dout[]/full/empty`；参数 `DATA_WIDTH`、`ADDR_WIDTH`（深度=2^n）。
- 功能：双时钟异步 FIFO，用**格雷码指针**跨时钟域；`full`/`empty` 由同步后的对侧指针判断；memory 用数组。
- 测试：写/读两个独立时钟；写入序列、按序读出并比对；验证满/空标志；输出 `PASS`。
- 注意：禁止用 bin 指针直接跨域；格雷码在两端各自打拍。

### 示例卡 2：color\_space（T10，display，YCbCr→RGB）

- 端口：`clk / rst_n / pixel_valid / y,cb,cr[7:0]` → `pixel_valid_out / r,g,b[7:0]`；`valid` 握手（兼容 vga\_timing）。
- 功能：BT.601 limited-range 定点矩阵 `R=1.164(Y-16)+1.596(Cr-128)` 等；YUV444 直接进入，YUV420 需先上采样/去交错。
- 测试：喂已知 Y/Cb/Cr，核对 RGB（手算一组），`PASS`。
- 注意：彩色差值用定点（移位/乘法器），避免浮点。

### 示例卡 3：key\_filter（T17，interact）

- 端口：`clk / rst_n / key_in[3:0]` → `key_out[3:0]`，参数 `CNT_MAX`（消抖时钟数）。
- 功能：按键消抖 + 边沿检测（长按可选）；输出稳定后的有效键值。
- 测试：给带抖动的按键，输出稳定的 `key_out`，`PASS`。

***

## 5. 实现流程（里程碑）

| 里程碑           | 内容                                                                                                                                       | 交付物                                       | 验收                                                                                       | 状态              |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- | ---------------------------------------------------------------------------------------- | --------------- |
| M1 地基         | vga\_timing、image\_enhance、async\_fifo、key\_filter、sw\_filter、seg\_driver、dual\_led、beep、reset\_gen                                      | 各模块 RTL+tb                                | 各自仿真 PASS                                                                                | \[U]            |
| M2 数据通路       | sd\_spi、sd\_reader、fat32\_scan、fat32\_file\_reader、bmp\_parser、bmp\_pixel\_stream、vseq\_reader、vseq\_yuv\_unpack                         | 扇区/索引/文件流/BMP像素/解析                   | 单元仿真正确                                                                                   | 上述模块 \[U]；P0 media chain 已 \[C] |
| M2.5 文件/像素流   | fat32\_file\_reader、bmp\_pixel\_stream、framebuffer\_writer、frame\_buffer\_manager、line\_prefetcher、line\_buffer\_pingpong、sdram\_arbiter | FAT32→pixel→framebuffer→display-order RGB | 端到端 \[C] | **P0-01~07 \[U\]；P0-08 \[C-sub\]；P0-09 \[C\]，P0 Frozen** |
| M3 帧缓存        | frame\_buffer\_manager、framebuffer\_writer、line\_prefetcher、sdram\_arbiter、sdram\_adapter、line\_buffer\_pingpong、APUG011                 | 缓存读写/无撕裂                                  | \[C] mock/vendor simulation；\[S] TD synthesis/P\&R/timing；\[B] hardware SDRAM validation | ❌               |
| M4 显示处理       | color\_space、image\_scaler、transition、osd\_overlay、audio\_visual                                                                         | 处理流水线                                     | 单元仿真                                                                                     | \[U]            |
| M5 官方 HDMI/音频 | hdmi\_video\_adapter、hdmi\_audio\_adapter、APUG092                                                                                        | HDMI 出图+音                                 | \[S] TD synthesis/P\&R/timing；\[B] HDMI 出图/出声                                            | ❌               |
| M7 集成 top     | system\_top、hx4s20c\_top、constraints                                                                                                     | 完整设计                                      | \[S] TD SYNTH/P\&R + \[B]/\[L] 上板 ≥2h                                                    | ❌               |

***

## 6. 仿真验证（每个模块）

- 在 `sim_tb/<子系统>/tb_<模块>.v` 写**激励 + 自检**（`$error` 计数，结尾 `$display("PASS/FAIL")`）。
- 编译需带上被测模块**及其例化的子模块** .v；在 `sim_work` 下：
  ```powershell
  cd sim_work
  vlib work
  vsim -c -do ../sim_tb/<子目录>/run_<模块>.do
  ```
- `run_<模块>.do` 固定为：`vlib work; vlog <dut.v> <tb.v>; vsim <tb>; run -all; quit -f`。
- 集成测试：需要时建 `tb_mini_top` 例化多个模块（如 vga\_timing + 彩条 + image\_enhance）验证**模块连接/接口匹配**。

***

## 7. 集成路径（从模块到 top）

1. P0：P0-01~07 `[U]`，P0-08 `[C-sub]`，P0-09 `[C]`；**P0 Frozen**。
2. P1：`sdram_adapter` 对接 APUG011；`hdmi_video_adapter` + APUG092 EG wrapper。
3. P1：`hx4s20c_top` 例化 PLL/APUG011/APUG092/SD/HDMI PHY，完成 TD synthesis/P\&R。
4. P2：接入基础 HDMI audio、OSD/transition/brightness/audio visual。

***

## 8. 协作与 PR

- 每个模块一个 PR；提交信息 `type(scope): subject`。
- 流程：1 人开发（pull main→分支→改→PASS→push→PR）→ 2 人审查（可拉分支本地测）→ 均为 Approve → Squash and merge。
- 厂商 IP 模块在 PR 描述标注“**已留注释，需人工 TD 例化核对**”。

***

## 9. 验收总表（对齐评分）

| 评分项         | 覆盖模块                                                                                     | 目标           |
| ----------- | ---------------------------------------------------------------------------------------- | ------------ |
| 基础①核心功能     | sd\_spi/sd\_reader/fat32\_file\_reader/bmp\_pixel\_stream/frame\_buffer\_manager/APUG092 | 读+显示+切图/轮播   |
| 基础②显示稳定     | frame\_buffer\_manager/line\_buffer\_pingpong/APUG092                                    | ≥2h、无花屏撕裂    |
| 基础③基础音频     | hdmi\_audio\_adapter/tone\_gen/APUG092                                                   | HDMI 出声      |
| 基础④工程规范     | 全部                                                                                       | 模块化/注释/约束/文档 |
| 扩展①字幕图层     | osd\_overlay                                                                             | 时间戳+滚动标语     |
| 扩展②转场       | transition                                                                               | 淡入淡出/滑动      |
| 扩展③缩放       | color\_space/image\_scaler                                                               | 多分辨率适配       |
| 扩展④实时调节+OSD | image\_enhance/menu\_fsm                                                                 | 亮度/对比度+参数显示  |
| 扩展⑤音频可视化    | tone\_gen/可视化                                                                            | 频谱/波形叠加      |


## P0 最终冻结状态（2026-08-31）

```text
P0-01 fat32_file_reader       [U]
P0-02 bmp_pixel_stream        [U]
P0-03 framebuffer_writer      [U]
P0-04 frame_buffer_manager    [U]
P0-05 line_buffer_pingpong    [U]
P0-06 line_prefetcher         [U]
P0-07 sdram_arbiter           [U]
P0-08 framebuffer/mock chain  [C-sub]
P0-09 full P0 media chain     [C]
```

实测记录：

- `sdram_arbiter`: CASE0~CASE8 PASS, checks=39。
- `framebuffer mock chain`: CASE-GOLDEN + CASE0~CASE3 PASS, checks=1495。
- `P0-09`：CASE-GOLDEN+CASE0~CASE3 PASS（checks=1698），完整媒体主链 `[C]`。
- P0 Implementation Freeze v1.0 已生效；P1 不得为适配 vendor IP 随意改 P0 业务接口，差异优先由 adapter/wrapper 吸收。
