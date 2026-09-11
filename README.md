# 基于 EG4S20 的 HDMI 多媒体播放系统

> **TD5.6.2 打开方式（2026-09-11 修复）**：项目根目录现在只保留一个可打开的 `FPGA_Competition_HDMI.al`，它已经切换到 **P1-04B HX4S20C HDMI_B board-safe** 配置，TOP=`p1_hx4s20c_hdmi_board_top`，ADC=`constraints/p1_hx4s20c_hdmi_board.adc`，SDC=`constraints/p1_hx4s20c_hdmi_board.sdc`。旧 P1 工程定义已保存到 `docs/olds/td_projects/*.reference.txt`，不要再从根目录选择旧 `.al`。



 > **P1 当前证据（更新至 2026-09-11）**：P1-01 `sdram_adapter v0.4` 已完成 `[U]` **PASS(61)**，strict arbiter→adapter chain `[C-sub]` **PASS(42)**。P1-02A official protected APUG011 + IS42 **[C-sub] PASS(24)**。P1-02B 已在 **TD5.6.2 / V5.6.71036** 完成 SynOpt + PhyOpt(place+route) + BitGen，并正式达到 **`[S]`**：150 MHz / 6.666 ns 下 setup errors=0、WNS=+0.059 ns、TNS=0；hold errors=0、minimum slack=+0.260 ns、TNS=0；minimum period=6.607 ns，Max Freq=151.355 MHz。`EG_PHY_PLL` 与 `EG_PHY_SDRAM_2M_32` 均正常实现，原 baseline 9 条 setup failure 已全部消失。

> 2026 全国大学生嵌入式芯片与系统设计竞赛 · FPGA 创新设计赛道 · 安路选题一  
> 平台：HX4S20C / EG4S20BG256  
> 作品定位：校园/园区信息发布与应急广播终端；运行时不依赖外部 CPU/MCU。

## 当前工程状态

状态证据统一使用：`[U] UNIT PASS`、`[C-sub] SUB-CHAIN PASS`、`[C] CHAIN PASS`、`[S] TD SYNTH/P&R PASS`、`[B] BOARD PASS`、`[L] LONG-RUN PASS`。

```text
P0-01 ~ P0-06             [U]
P0-07 sdram_arbiter       [U] (39 checks)
P0-08 framebuffer chain   —  (historical PASS; rerun required after arbiter v1.1)
P0-09 full media chain    [C] (1698 checks)
P0                         Implementation Freeze v1.0
P1-01 v0.4               [U] / [C-sub] (61 / 42 checks)
P1-02A official core      [C-sub] (24 checks)
P1-02B TD integration     [S] (150MHz setup/hold 0 violations)
TD SDRAM backend          [S] (WNS=+0.059ns; hold min slack=+0.260ns)
P1-03A HDMI adapter       [U] PASS(24); line-buffer sub-chain [C-sub] PASS(57)
P1-03B pattern provider     [U] PASS(37); protected-core Questa = TOOL_BLOCKED
P1-04A 720p clock experiment SynOpt PASS; 75/375MHz STA FAIL（非 board-safe）
P1-04B official-640 board    candidate：真实 HDMI_B ADC + working 25/125MHz PLL 已导入
Hardware                   开发板/TF卡/显示器已到位；官方 lab_ex4_tf 已真板 PASS，本项目尚无 [B]/[L]
```

P0 `[C]` 只证明纯 RTL + mock SDRAM 的端到端媒体链；不等于 APUG011/APUG092、TD 完整构建或真板通过。

## 四份权威文档

- `docs/01_architecture.md`：P0→P4 系统架构、冻结边界、vendor/CDC 红线；
- `docs/02_implementation_goals.md`：实现目标、内容格式、最终验收边界；
- `docs/03_plan_and_status.md`：**唯一进度/模块状态权威**，含 `[U]/[C]/[S]/[B]/[L]` 证据；
- `docs/04_use_cases.md`：信息发布、应急广播、交互与答辩使用场景。

`docs/olds/` 仅保存历史资料，不作为当前架构或状态依据。
`docs/evidence/` 保存测试产生的结果、证据等，供参考。

## 当前主数据链

```text
TF/FAT32 → BMP → RGB888
               ↓
      framebuffer_writer
               ↓
      frame_buffer_manager
               ↓
        sdram_arbiter
               ↓
        sdram_adapter            (P1-01; [U]，strict chain 已 [C-sub])
               ↓
   APUG011 sdr_as_ram / EG SDRAM (P1 vendor boundary)
               ↓
        line_prefetcher
               ↓
     line_buffer_pingpong
               ↓
      display-order RGB888
               ↓
  APUG092 HDMI path（后续 P1）
```

P1-01 的 `sdram_adapter` 根据 APUG011 v1.2 application-side 语义实现：21-bit/32-bit、读写互斥、init/refresh/busy 门控、4-word 地址组、`Sdr_rd_en` 返回。为保持 P0 任意单 word 地址契约，adapter 将每个抽象 word 转换为一个 4-word 对齐 micro-group；写入用 `App_wr_dm` 屏蔽另外 3 words，读取只返回目标 lane。

## 仿真

P0 冻结回归：

```powershell
cd sim_work
vsim -c -do ../sim_tb/integration/run_p0_media_chain.do
```

P1-01（当前仿真环境：QuestaSim 10.7c）：

```powershell
cd sim_work
vsim -c -do ../sim_tb/framebuf/run_sdram_adapter.do
vsim -c -do ../sim_tb/framebuf/run_sdram_arbiter_adapter_chain.do
```

当前 candidate-2 已实测 `tb_sdram_adapter` **PASS (checks=61)**，`sdram_adapter v0.4` 正式为 `[U]`；`tb_sdram_arbiter_adapter_chain` **PASS (checks=42)**，因此 arbiter→adapter→strict APUG011-like model 为 `[C-sub]`。

P1-02A 已实测 **PASS (checks=24)**：125 MHz/180° model-safe 下 tCK/tRCD=0 violation，App read-DM/physical READ DQM 均 0 violation，addr5/addr8 正确读回 `0x11223344/0xA5A55A5A`。因此 official protected APUG011 behavioral chain 正式 `[C-sub]`。P1-02B 当前把官方原始 `clk_pll.v`、`global_def.v`（TD Global Include）、三个独立 protected `.enc.v`、`apug011_core_wrapper` 与 `EG_PHY_SDRAM_2M_32` 接入 TD-only harness；25 MHz ref 只是官方 reference harness，不是最终 HX4S20C 50 MHz board clock。旧 `apug011_td_compile_unit.v` 已停用且不进入 TD source。

P1-02B 的 BIST **PASS (checks=9)**，`p1_apug011_bist` 为 `[U]`。candidate-2 最终六项 RTL 回归全部 PASS，并在 **TD5.6.2 / V5.6.71036 GUI** 完成 SynOpt、PhyOpt 与 BitGen；TOP=`p1_apug011_td_top`，ADC 为空，SDC=`constraints/p1_apug011_td.sdc`，150 MHz / 6.666 ns 未放宽。最终 setup/hold 均无 violation，因此 TD SDRAM backend 正式记 `[S]`。详细 closure 证据见 `docs/develop_records/P1-02B_TD56_TIMING_CLOSURE_CANDIDATE2.md`.

## P1-03 已获得的验证证据

P1-03A 的 project-owned 视频契约已经通过 QuestaSim 10.7c：`hdmi_video_adapter` **PASS(24)**，正式记 `[U]`；真实 `line_buffer_pingpong -> hdmi_video_adapter` 子链 **PASS(57)**，正式记 `[C-sub]`。`hdmi_test_pattern_line_provider` 同样 **PASS(37)**，记 `[U]`。这些结果都来自本轮实际 transcript，而不是代码存在性判断。

APUG092 protected core 在 Questa 10.7c 中可 `vlog` 编译（Errors=0），但 `vsim` optimization 在 protected region 报错 4 次，因此其行为仿真状态记为 **TOOL_BLOCKED**，不判项目 RTL FAIL。TD5.6.2 SynOpt 则能够正常 elaboration protected transmitter、`hdmi_phy_wrapper` 和四路 `EG_LOGIC_ODDR`，说明 synthesis integration 边界成立。

P1-03B 仍保留 1280x720 injected-clock harness 作为高分辨率 transport/STA 实验边界；它不是当前可烧板工程。

## P1-04A 720p 实验结论

`FPGA_Competition_HDMI_P1-04A.al` 的 50MHz -> 75/375MHz experimental clock path 已完成 SynOpt，但 TD5.6.2 STA 未闭合：375MHz 有 setup violation，75MHz 有 hold violation，同时存在 removal violation。因此 P1-04A **明确保留为实验分支，禁止烧板**；不能因为 synthesis 成功就升级 `[S]`。

这一轮最重要的新事实来自用户已实际运行成功的官方 `lab_ex4_tf`：HX4S20C HDMI_B 使用 640x480、25MHz pixel / 125MHz serial、50MHz board clock，并有已验证 package pin。项目据此进入 P1-04B。

## P1-04B board-safe candidate

新增独立工程 `FPGA_Competition_HDMI_P1-04B.al`，TOP=`p1_hx4s20c_hdmi_board_top`。它不再复用 P1-04A 75/375MHz 手写 PLL，而使用用户 working official `video_pll.v` 报告出的完整 EG PLL 参数，生成 **25MHz pixel + 125MHz serial，均 0deg**。输出模式严格匹配 working sample：**640x480 / 800x525 / VIC=1**。

真实板级约束已经写入：

- board `clk`: R7 / LVCMOS33
- HDMI_B D0/D1/D2/CLK P: G5/F1/E1/C3 / LVDS33
- DDC SCL/SDA: P2/R2 / LVCMOS33

P1-04B 不使用 KEY1/KEY2，也不暴露需要额外 LED pin 的 debug port，因此第一次烧板不会受到用户观察到的 KEY1/KEY2 标号疑似互换问题影响。

640x480 是**board-safe bring-up baseline**，与官方样例相同，不低于官方样例；它不是最终性能目标。P1-04B 真板点亮后再重新打开 720p PLL/STA 优化，1080p/双板仍等待高串行速率 PHY feasibility 证据。详细见 `docs/develop_records/P1-04B_HX4S20C_OFFICIAL640_BOARD_SAFE_CANDIDATE.md`。

## 工程规则

- `FPGA_Competition_HDMI.al` 只列可综合 RTL；testbench/mock 不进入 TD synthesis source；
- APUG011/APUG092/PLL/IO/管脚必须来自官方资料，禁止猜 vendor 端口和约束；
- P0 已冻结；vendor 时序差异优先由 P1 adapter/wrapper 吸收；
- `.git/` 只由本地仓库维护，不应随项目覆盖包复制；
- 每次迭代：代码/文档/`.al` → QuestaSim 10.7c / TD 验证 → 依据证据提升状态 → PR/review。
