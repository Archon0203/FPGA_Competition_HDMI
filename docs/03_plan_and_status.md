# 03 · 计划、验证状态与模块矩阵

> 本文是项目进度的唯一权威。状态表示“已有证据的最高等级”，不是主观完成百分比。

## 1. 状态体系

| 状态 | 含义 | 必要证据 |
|---|---|---|
| `[U]` | **UNIT PASS** | 模块自检 testbench PASS；关键边界/异常有主动检查 |
| `[C-sub]` | **SUB-CHAIN PASS** | 局部多模块链路真实握手联调 PASS，但不是阶段完整端到端 |
| `[C]` | **CHAIN PASS** | 阶段定义的端到端数据链 PASS |
| `[S]` | **TD SYNTH/P&R PASS** | synthesis + P&R + timing + resource + RAM inference + clock/constraints 均人工检查 |
| `[B]` | **BOARD PASS** | 真 HX4S20C 上目标功能通过 |
| `[L]` | **LONG-RUN PASS** | 真板长稳 ≥2h，并完成切换/压力测试 |
| `—` | 尚未达到上述证据 | 不是失败，只表示待实现或待验证 |

规则：单元 `[U]` 不能写成“系统功能完成”；旧文档中的 `√/×/✅/❌` 不再作为工程状态。

### 1.1 文档组织规范

- 当前有效的架构/设计文档仅维护 `docs/01_architecture.md`、`docs/02_implementation_goals.md`、`docs/03_plan_and_status.md`、`docs/04_use_cases.md`。
- 历史/已被替换的旧版 `01_*` ~ `12_*` 文档只留存于 `docs/olds/`，用于回溯，**不再更新**。
- 开发过程记录（模块接口说明、测试向量、回归记录、阶段 release/note 等）统一放在 `docs/develop_records/`，不要散落到 `docs/` 根目录或与架构文档混排。
- `docs/` 根目录只放“当前权威”的架构、目标、计划/状态、用例文档，避免目录混乱。

## 2. 当前快照（2026-09-01）

```text
TD Verilog source entries 42 files in `.al`（TD6.2 native：project RTL + official clk_pll + GlobalInclude + 3 protected sources + wrapper/BIST/TD harness）
vendor reference subset   APUG011 v1.2 read-only protected core + exact official clk_pll.v
sim_tb/tb_*.v             40 testbenches（新增 P1 TD BIST unit TB）
P0 frozen reference       P0-09 [C] PASS (1698)；bmp_parser PASS (8)
P1-01 v0.3               COMPLETE：adapter [U] PASS (61)；strict chain [C-sub] PASS (42)
P1-02A official core      [C-sub] PASS (24)：125 MHz model-safe / 180°；readback/tCK/tRCD/DQM 全通过
P1-02B TD candidate       TD6.2.1 native protected-source；Syn Opt 已完成，setup FAIL；P&R worker blocked
P0-01 ~ P0-07             [U]
P0-08 framebuffer chain   [C-sub]
P0-09 full media chain    [C]
P1/P2/P3/P4 system chain  尚未达到 [C]
TD SDRAM backend          等待 synthesis/P&R/timing/resource 证据；尚无 [S]
Hardware                  尚无 [B]/[L]
```

当前 P1-02B candidate 的 `.al` 已把 TOP 切到 `p1_apug011_td_top`，按 APUG011 官方工程方式加入 `global_def.v`（`GlobalIncluded=true`）、三个独立 protected `.enc.v`、官方 `clk_pll.v`、wrapper/BIST，并只绑定 `constraints/p1_apug011_td.sdc` 这一份**时钟级 synthesis harness 约束**；`ADC_FILE` 仍为空，现有 board pin 模板不参与本轮。该 harness 使用 APUG011 官方参考的 25 MHz 输入 PLL（150 MHz 0°/180° SDRAM clocks），**不是 HX4S20C 最终 50 MHz board top**。因此本轮即使 TD `[S]`，也只说明 SDRAM backend 子系统通过 synthesis/P&R/timing/resource/clock 检查，不代表最终系统或板级 pin `[S]/[B]`。

## 3. P0 冻结证据

| ID | 对象 | 状态 | 已记录回归证据 |
|---|---|---|---|
| P0-01 | `fat32_file_reader` | `[U]` | fragmented chain / file_size / abnormal FAT cases；18 checks |
| P0-02 | `bmp_pixel_stream` | `[U]` | padding 0/1/2/3、17/640/641、offset gap、异常 header；13393 checks |
| P0-03 | `framebuffer_writer` | `[U]` | stall/FIFO/address/RGB word；1345 checks |
| P0-04 | `frame_buffer_manager` | `[U]` | A/B ownership、frame-boundary swap、failure reuse；166 checks |
| P0-05 | `line_buffer_pingpong` | `[U]` | golden literal + 连续行输出；2204 checks |
| P0-06 | `line_prefetcher` | `[U]` | multi-outstanding、stall、timeout/recovery；2713 checks |
| P0-07 | `sdram_arbiter` | `[U]` | read priority、delayed/zero-latency response、protocol error；39 checks |
| P0-08 | framebuffer + mock SDRAM mini-chain | `[C-sub]` | manager→writer→arbiter→mock→prefetch→linebuffer；1495 checks |
| P0-09 | full P0 media chain | `[C]` | fragmented FAT32 + BMP + framebuffer + readback；**1698 checks** |

P0-09 冻结命令：

```powershell
cd sim_work
vsim -c -do ../sim_tb/integration/run_p0_media_chain.do
```

冻结结果：

```text
PASS: P0 media chain end-to-end all cases passed (checks=1698)
```

P0 进入维护模式；没有 Architecture Change Request 不增加功能、不随意改接口。

## 4. 全部现有 RTL 模块状态

P0 冻结基线中的 33 个 `src/*.v` 已包含在既有 36/36 回归中。P1-01 新增 `sdram_adapter`，P1-02 加入 `apug011_core_wrapper`、BIST 与 TD harness；TD 6.2.1 使用官方 Global Include + 独立 protected-source 组织；vendor protected core/PLL 不计 project-owned 模块状态。当前仿真环境为 **QuestaSim 10.7c**。

2026-09-01 实测已确认当前 `sdram_adapter v0.3`：`tb_sdram_adapter` **PASS (checks=61)**，因此 `[U]`；`tb_sdram_arbiter_adapter_chain` **PASS (checks=42)**，因此 arbiter→adapter→strict model `[C-sub]`。P1-02A official protected-core integration 也已 **PASS (checks=24)**：125 MHz model-safe / 180° 下 tCK=0、tRCD=0、App read-DM=0、physical READ DQM=0，且 addr5/addr8 分别读回 `0x11223344/0xA5A55A5A`，因此 official APUG011 behavioral memory sub-chain 正式为 `[C-sub]`。P0-09 同轮重新回归 **PASS (1698)**，冻结 `[C]` 保持。

| 子系统 | 模块 | 阶段角色 | 当前状态 | 备注 |
|---|---|---|---|---|
| top | `reset_gen` | support/P1 | `[U]` | 保留 support；P1-02B candidate 的 `.al` TOP 已切到 TD harness |
| storage | `sd_spi` | P1 support | `[U]` | 字节级 SPI；真卡仍需 `[B]` |
| storage | `sd_reader` | P1 support | `[U]` | 命令 FSM；SDHC CMD58/CCS 等真卡语义待板级确认 |
| storage | `fat32_scan` | P1/P3 support | `[U]` | 当前只扫描根目录第一 sector |
| storage | `bmp_parser` | P0 support | `[U]` | **恢复 P0 Freeze v1.0**：含 `start` 新文件契约、24-bit BI_RGB 严格 header 校验 |
| storage | `fat32_file_reader` | **P0** | `[U]` | P0-01 |
| storage | `bmp_pixel_stream` | **P0** | `[U]` | P0-02 |
| storage | `vseq_reader` | P3 | `[U]` | `.vseq` header/body byte stream |
| storage | `vseq_yuv_unpack` | P3 | `[U]` | YUV444 解包 |
| framebuf | `async_fifo` | support | `[U]` | CDC 工具模块 |
| framebuf | `framebuffer_writer` | **P0** | `[U]` | P0-03 |
| framebuf | `frame_buffer_manager` | **P0** | `[U]` | P0-04；图片 A/B |
| framebuf | `line_buffer_pingpong` | **P0** | `[U]` | P0-05；active-line continuity |
| framebuf | `line_prefetcher` | **P0** | `[U]` | P0-06 |
| framebuf | `sdram_arbiter` | **P0** | `[U]` | P0-07 |
| framebuf | `sdram_adapter` | **P1** | `[U]` | **v0.3 PASS (61)**；READ/IDLE `App_wr_dm=0000`，strict chain `[C-sub]`(42) |
| top | `apug011_core_wrapper` | **P1-02A/B** | `[C-sub]` | thin wrapper；official protected core + IS42 model PASS(24)；P1-02B 已加入 TD harness |
| top | `apug011_td_compile_unit` | historical | `—` | **DEPRECATED**；TD6.2 实测证明不应通过 `include` 聚合 protected sources；不进入 `.al` |
| top | `p1_apug011_bist` | **P1-02B support** | `—` | synthesis observability/BIST traffic source；新增 unit TB 待跑 |
| top | `p1_apug011_td_top` | **P1-02B** | `—` | official 25MHz ref PLL + 150MHz 0°/180° + APUG011 + EG internal SDRAM；等待 `[S]` |
| display | `vga_timing` | P1/P2 support | `[U]` | timing/test source；正式 HDMI 需 APUG092 interface 对齐 |
| display | `color_space` | P3 | `[U]` | YCbCr→RGB |
| display | `image_scaler` | P2/P3 | `[U]` | 最近邻映射基础 |
| display | `image_enhance` | P2 | `[U]` | 亮度/对比度 |
| display | `transition` | P2 | `[U]` | 淡入/擦拭基础 |
| display | `osd_overlay` | P2 | `[U]` | 8×16 字模基础 |
| display | `yuv420_upsample` | P4 | `[U]` | 组件可用，完整 YUV420 链未 `[C]` |
| display | `tmds_encoder` | reference | `[U]` | **教学/协议参考，不进入正式 APUG092 主链** |
| audio | `tone_gen` | P2 | `[U]` | 测试/提示音源 |
| audio | `audio_visual` | P2 | `[U]` | 低资源振幅包络柱 |
| audio | `hdmi_audio_pack` | reference | `[U]` | IEC60958 教学参考，不进入正式 APUG092 主链 |
| interact | `key_filter` | P2 | `[U]` | 按键消抖/事件 |
| interact | `sw_filter` | P2 | `[U]` | 拨码消抖 |
| interact | `menu_fsm` | P2 | `[U]` | 播放/参数/应急控制基础 |
| interact | `seg_driver` | P2 | `[U]` | 数码管 |
| interact | `dual_led` | P2 | `[U]` | 状态灯 |
| interact | `beep` | P2 | `[U]` | 蜂鸣器 |
| app | `app_scenario` | P2 | `[U]` | 信息发布/应急状态机基础 |

额外集成 TB：

| 集成对象 | 状态 | 说明 |
|---|---|---|
| `tb_mini_top` | `[C-sub]` | 早期纯显示处理 mini-chain；只证明该子链连接，不代表正式 HDMI |
| `tb_framebuffer_mock_chain` | `[C-sub]` | P0-08 |
| `tb_p0_media_chain` | `[C]` | P0-09，当前最重要的软件级端到端证据 |
| `tb_sdram_adapter` | `[U]` | v0.3 **PASS(61)**；含 read-DQM 断言 |
| `tb_sdram_arbiter_adapter_chain` | `[C-sub]` | v0.3 **PASS(42)** |
| `tb_sdram_adapter_apug011_official` | `[C-sub]` | **PASS(24)**；125MHz/180°，readback + tCK/tRCD + app/physical DQM 全通过 |
| `tb_p1_apug011_bist` | `—` | P1-02B harness traffic-source unit candidate；等待 QuestaSim 10.7c |

## 5. P1 计划与状态

P1 目标是把 P0 的抽象接口接到官方 IP、TD 和真板，不重复实现厂商已有协议层。

| ID | 任务 | 目标证据 | 当前 |
|---|---|---|---|
| P1-01 | `sdram_adapter` 对接 APUG011 application-side；4-word micro-group / mask / response-filter | adapter `[U]` + arbiter-memory sub-chain `[C-sub]` | **v0.3 COMPLETE：PASS(61) + strict chain PASS(42)** |
| P1-02 | APUG011 官方 protected core + TD 集成 | official-core `[C-sub]`，随后 TD `[S]` | **P1-02A COMPLETE `[C-sub]` PASS(24)；P1-02B 主工程 Syn Opt 已完成且 protected/primitive 均展开；setup 仍 FAIL，P&R 尚无有效结果，因此未获 `[S]`** |
| P1-03 | `hdmi_video_adapter` + APUG092 EG wrapper/PHY；验证整行连续 | video sub-chain `[C-sub]`，随后 `[B]` | `—` |
| P1-04 | `system_top` / `hx4s20c_top` / PLL / **官方 HX4S20C ADC/SDC** | final design `[S]` | `—` |
| P1-05 | 真板 SDRAM + HDMI 640×480 出图 | `[B]` | `—` |
| P1-06 | 真 TF 卡读块/文件 + A/B 图片加载与显示 | `[B]` | `—` |
| P1-07 | 长稳/快速切换压力测试 | `[L]` | `—` |

P1-01 验证命令（当前仿真环境：QuestaSim 10.7c）：

```powershell
cd sim_work
vsim -c -do ../sim_tb/framebuf/run_sdram_adapter.do
vsim -c -do ../sim_tb/framebuf/run_sdram_arbiter_adapter_chain.do
```


P1-02A official protected-core 验证命令：

```powershell
cd sim_work
vsim -c -do ../sim_tb/framebuf/run_sdram_adapter_apug011_official.do
```

P1-02A 已正式完成。最终 model-safe 验证使用 **125 MHz / 180°**（只为满足随包 IS42 -7 外部模型的 tCK/tRCD envelope），结果 **PASS (checks=24)**：tCK violation=0、tRCD violation=0、App read-DM violation=0、physical READ DQM violation=0、physical READ command count>0；addr5/addr8 分别读回 `0x11223344` 与 `0xA5A55A5A`。因此 `sdram_adapter -> official protected APUG011 -> official IS42 model` 正式记 `[C-sub]`。这不把最终硬件频率降为 125 MHz；官方参考 PLL 与 P1-02B 仍使用 150 MHz 0°/180°。

同轮回归：`bmp_parser PASS(8)`、P0-09 **PASS(1698)**、`sdram_adapter v0.3 PASS(61)`、strict arbiter-adapter chain **PASS(42)**。P0 `[C]` 和 P1-01 `[U]/[C-sub]` 均保持有效。

P1-02 继续拆成两个有证据边界的子步骤：

- **P1-02A：COMPLETE `[C-sub]`**。QuestaSim 10.7c 已验证 project adapter 与官方 protected controller/behavioral SDRAM model 的数据完整性和 DQM 语义。
- **P1-02B：当前 TD6.2.1 native-source candidate**。已完成最小判别实验：在 APUG011 官方 `sdram_as_ram.al` 副本中将 `sdr_as_ram.enc.v` 设为 Top，移除仅针对 demo top 的 `io.adc` 后，TD 6.2.1 Engineer 168116 执行 Syn Opt **0 ERROR**（存在 warnings，尚待主工程报告分类）。这证明 protected RTL 可被 TD 6.2.1 解密/elaborate/synthesize，先前主工程的 `**`/black-box 不是“缺 APUG011 专用授权”，而是 source organization 错误。主 `.al` 现严格镜像官方工程：`global_def.v` 设 `GlobalIncluded=true`，`sdr_as_ram.enc.v` / `sdr_init_ref.enc.v` / `sdr_wrrd.enc.v` 三个文件独立作为 Verilog source；旧 `apug011_td_compile_unit.v` 停用且不进入 `.al`。PLL 仍使用官方 APUG011 v1.2 原始 `clk_pll.v`（25 MHz ref -> 150 MHz 0°/180°），并按官方 top 精确例化 `EG_PHY_SDRAM_2M_32`。`p1_apug011_bist` 产生两写两读流量，保证整条 backend 在综合中可观察。

P1-02B 的 `constraints/p1_apug011_td.sdc` **只有 clock constraint，没有 pin/IOSTANDARD**：25 MHz ref clock + TD 6.2.1 当前命令 `derive_clocks`。此前 `derive_pll_clocks` 会触发 CRITICAL-WARNING（obsolete），因此本版已替换；禁止为了消除 setup 负裕量而放宽 150 MHz 目标。本轮不使用历史 `eg4s20bg256_pins.cst`，也不把官方 demo 的 T14/R15 pin 复制到 HX4S20C。TD synthesis + P&R + timing/resource/clock/primitive 检查全部通过后，可把 **SDRAM backend 子系统**提升 `[S]`；最终 50 MHz HX4S20C board PLL、board ADC/SDC 和系统 top 仍属于 P1-04，不能提前记 system `[S]`。


### P1-02B 当前 TD6.2.1 实测（Syn Opt 完成，P&R 待恢复）

主工程 native-source 组织已完成一次有效综合：`read_design/opt_rtl/opt_gate` 全部完成并输出 gate DB。`sdr_as_ram` 非黑盒，其内部 `sdr_init_ref`/`sdr_wrrd` 已展开；`EG_PHY_PLL`、`EG_LOGIC_BUFG` 和 `EG_PHY_SDRAM_2M_32` 均被识别。综合资源快照约 LUT 282、FF 283、PLL 1/4，internal SDRAM 以物理 MACRO 计而不是 ERAM/BRAM。

该次 timing 仅作为 **pre-P&R 诊断证据**：setup WNS=-5958 ps、TNS=-389433 ps、115 endpoints；hold WNS=+549 ps。由于当时 SDC 仍用了 TD6.2.1 已标记 obsolete 的 `derive_pll_clocks`，并且 `phy_1` 未完成，不能把这些数值当最终时序结论。本版改用 `derive_clocks` 后必须重新 Syn Opt，再完成 P&R 后读取最终 WNS/TNS。

`phy_1` 当前属于 **FLOW BLOCKED，不是 P&R FAIL**：DeepSeek 在执行 `reset_runs syn_1 -f` 后，worker `run.exe` 只输出 banner 即停在初始化，`wait_run` 无法完成。因此没有合法的 P&R PASS/FAIL 证据，也没有 `[S]`。优先用本 candidate 的干净工程从 GUI 重新 Syn Opt → Physical Design，不复用被 reset 的旧 run 产物；若 GUI 仍卡住，再保存 TD log/run worker 日志定位工具流程问题。

P1-02B candidate 先跑新增 BIST unit：

```powershell
cd sim_work
vsim -c -do ../sim_tb/top/run_p1_apug011_bist.do
```

然后用 **Anlogic TD 6.2.1 Engineer 168116** 打开根目录 `FPGA_Competition_HDMI.al`，确认 TOP=`p1_apug011_td_top`、ADC 为空、SDC=`constraints/p1_apug011_td.sdc`，依次执行 Synthesis 与 Physical Design。验收必须记录：protected core 是否成功解密/展开、`EG_PHY_PLL` 与 `EG_PHY_SDRAM_2M_32` 是否成功 elaborate/legalize、150 MHz generated clocks、worst slack、LUT/FF/PLL/SDRAM primitive 资源，以及全部 WARNING/ERROR。任何一个环节失败都不标 `[S]`。


P1 完成前最重要的资源检查：`line_buffer_pingpong` 的 RAM 数组故意不做整块 reset，以保留 ERAM inference 机会；只有 TD 报告确认后才能说“行缓存进了 ERAM”。

## 6. P2~P4 计划

| 阶段 | 重点 | 当前基础 | 阶段完成条件 |
|---|---|---|---|
| P2 | HDMI audio、OSD/状态栏、亮度/对比度、转场、音频柱、应急 UI、交互整合 | 相关组件多数 `[U]` | presentation 子链 `[C]` + 真板 `[B]` |
| P3 | YUV444 `.vseq` 短视频；frame scheduling；color-space + scaler | reader/unpack/color/scaler `[U]` | 视频端到端 `[C]` + 真板 `[B]` |
| P4 | YUV420、SDIO、720p、其他加分 | yuv420 组件 `[U]`；其余未实现 | 不阻塞主作品；按实测决定是否宣传 |

## 7. 验证与开发工作流

每次改动按固定闭环：

```text
main 最新基线
  → 新 feature/fix/docs 分支
  → RTL / TB / docs / .al 必要更新
  → QuestaSim 10.7c 回归
  → P1 起增加 TD synthesis/P&R
  → 真板阶段增加 board test
  → 证据足够后提升 [U]/[C]/[S]/[B]/[L]
  → PR + review + merge
```

工程规则：

- 一个 `src/<subsystem>/<module>.v` 对应一个 `sim_tb/<subsystem>/tb_<module>.v` 和运行脚本；
- 协议/缓存 TB 必须包含 adversarial cases：random stall、timeout、碎片 FAT、padding、读写争用、underflow/overflow 等；
- testbench/mock 不加入 TD synthesis source；
- 不提交 `sim_work/`、`.db/.area/.bit/.log` 等生成物；
- 对已有 `[U]/[C]` 模块改接口时，必须同步 TB 并重跑受影响链；
- `main` 不直接开发，走 feature 分支与 PR 审核。

## 8. 当前主要风险

| 风险 | 当前处理原则 |
|---|---|
| APUG011 时序与抽象 memory 契约不一致 | P1 adapter 吸收；用 busy/refresh/latency adversarial TB |
| APUG092 active line 断流 | P0 line prefetch + ping-pong 是硬约束；先仿真再上板 |
| TD RAM inference 不符合预期 | `[S]` 阶段必须查 resource/inference 报告，不凭 RTL 数组写法猜 |
| 约束错误 | 当前模板不使用；只接受官方 HX4S20C pin/clock 证据 |
| SD 真卡差异 | 真卡 `[B]` 前不把 SD reader `[U]` 宣传成已板级可用 |
| 功能膨胀 | P1 完成前不新增复杂特效；P4 不阻塞主线 |
| 文档漂移 | 只维护本文件的状态表；详细行为以 RTL/TB 为源 |
