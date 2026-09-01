# 基于 EG4S20 的 HDMI 多媒体播放系统


 > **P1 当前证据（2026-09-01）**：P1-01 v0.3 已完成：`sdram_adapter [U]` **PASS(61)**，strict arbiter→adapter chain `[C-sub]` **PASS(42)**。P1-02A 已完成：QuestaSim 10.7c 下 official protected APUG011 + official IS42 model **PASS(24)**，P0-09 同轮重新 **PASS(1698)**。P1-02B 的 TD 6.2.1 native-source 组织已经解决 protected-core black-box 问题：主工程 `syn_1` 已完整完成 read_design/opt_rtl/opt_gate 并生成 gate DB；`sdr_as_ram/sdr_init_ref/sdr_wrrd`、`EG_PHY_PLL/EG_LOGIC_BUFG` 与 `EG_PHY_SDRAM_2M_32` 均被识别。当前综合后 setup 仍失败（报告 WNS=-5958 ps，115 endpoints；hold 通过），而 `phy_1` 因 run worker 卡在初始化尚未产出有效 P&R，因此 **仍不能标 `[S]`**。TD 6.2.1 已明确提示 `derive_pll_clocks` obsolete，本 candidate 将 SDC 更新为 `derive_clocks`，必须重新 Syn Opt 后再以 P&R 后 timing 为准。

> 2026 全国大学生嵌入式芯片与系统设计竞赛 · FPGA 创新设计赛道 · 安路选题一  
> 平台：HX4S20C / EG4S20BG256  
> 作品定位：校园/园区信息发布与应急广播终端；运行时不依赖外部 CPU/MCU。

## 当前工程状态

状态证据统一使用：`[U] UNIT PASS`、`[C-sub] SUB-CHAIN PASS`、`[C] CHAIN PASS`、`[S] TD SYNTH/P&R PASS`、`[B] BOARD PASS`、`[L] LONG-RUN PASS`。

```text
P0-01 ~ P0-07             [U]
P0-08 framebuffer chain   [C-sub]
P0-09 full media chain    [C]  (checks=1698)
P0                         Implementation Freeze v1.0
P1-01 v0.3               [U] / [C-sub] (61 / 42 checks)
P1-02A official core      [C-sub] (24 checks)
P1-02B TD integration      —  (Syn Opt completed; setup failing; P&R pending)
TD final build             尚无 [S]
Hardware                   尚无 [B]/[L]
```

P0 `[C]` 只证明纯 RTL + mock SDRAM 的端到端媒体链；不等于 APUG011/APUG092、TD 完整构建或真板通过。

## 四份权威文档

- `docs/01_architecture.md`：P0→P4 系统架构、冻结边界、vendor/CDC 红线；
- `docs/02_implementation_goals.md`：实现目标、内容格式、最终验收边界；
- `docs/03_plan_and_status.md`：**唯一进度/模块状态权威**，含 `[U]/[C]/[S]/[B]/[L]` 证据；
- `docs/04_use_cases.md`：信息发布、应急广播、交互与答辩使用场景。

`docs/old/` 仅保存历史资料，不作为当前架构或状态依据。

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

当前已实测 `tb_sdram_adapter` **PASS (checks=61)**，`sdram_adapter v0.3` 正式为 `[U]`；`tb_sdram_arbiter_adapter_chain` **PASS (checks=42)**，因此 arbiter→adapter→strict APUG011-like model 为 `[C-sub]`。

P1-02A 已实测 **PASS (checks=24)**：125 MHz/180° model-safe 下 tCK/tRCD=0 violation，App read-DM/physical READ DQM 均 0 violation，addr5/addr8 正确读回 `0x11223344/0xA5A55A5A`。因此 official protected APUG011 behavioral chain 正式 `[C-sub]`。P1-02B 当前把官方原始 `clk_pll.v`、`global_def.v`（TD Global Include）、三个独立 protected `.enc.v`、`apug011_core_wrapper` 与 `EG_PHY_SDRAM_2M_32` 接入 TD-only harness；25 MHz ref 只是官方 reference harness，不是最终 HX4S20C 50 MHz board clock。旧 `apug011_td_compile_unit.v` 已停用且不进入 TD source。

P1-02B TD candidate 先验证 BIST：

```powershell
cd sim_work
vsim -c -do ../sim_tb/top/run_p1_apug011_bist.do
```

随后用 **TD 6.2.1 Engineer 168116** 打开根目录 `FPGA_Competition_HDMI.al`。本 candidate 的 TOP 是 `p1_apug011_td_top`，只使用 `constraints/p1_apug011_td.sdc` 的 25 MHz reference-clock/PLL 约束，**不绑定任何板级 ADC/pin**。先重新跑 Synthesis/Syn Opt（本版 SDC 已改用 TD6.2.1 的 `derive_clocks`），再跑 Physical Design/P&R；只有 P&R 后 timing/resource/PLL/`EG_PHY_SDRAM_2M_32`/constraints 均确认通过才给 SDRAM backend 标 `[S]`。

## 工程规则

- `FPGA_Competition_HDMI.al` 只列可综合 RTL；testbench/mock 不进入 TD synthesis source；
- APUG011/APUG092/PLL/IO/管脚必须来自官方资料，禁止猜 vendor 端口和约束；
- P0 已冻结；vendor 时序差异优先由 P1 adapter/wrapper 吸收；
- `.git/` 只由本地仓库维护，不应随项目覆盖包复制；
- 每次迭代：代码/文档/`.al` → QuestaSim 10.7c / TD 验证 → 依据证据提升状态 → PR/review。
