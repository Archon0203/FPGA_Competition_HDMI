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


### P1-04C HDMI Board Baseline（2026-09-11）

当前已完成：

```text
P1-04C [B] PASS
```

证据：

- HX4S20C 实板 HDMI_B 输出成功；
- 显示器稳定显示 640×480 彩条；
- HDMI_B 管脚、EG PHY、APUG092 transmitter、PLL 链路已闭环；
- TD5.6.2 SynOpt / PhyOpt / BitGen 均完成。

当前 HDMI baseline：

```text
50MHz
  ↓
EG PHY PLL
  ↓
25MHz pixel / 125MHz serial
  ↓
APUG092 HDMI transmitter
  ↓
HDMI_B
```

下一阶段在此 baseline 上替换视频源为 SDRAM framebuffer，不改变已经验证通过的 HDMI 物理链路。

## 2. 当前快照（2026-09-11）

```text
P1-02 `.al` source entries  42 files（已验证 closed APUG011 project）
P1-03B `.al` source entries 8 files（APUG092 protected core + EG PHY + project wrappers/harness，candidate）
vendor reference subset   APUG011 v1.2 read-only protected core + exact official clk_pll.v
sim_tb/tb_*.v             44 testbenches（P1-03A/B HDMI project-owned TB 已执行；protected core sim 被 Questa 工具阻塞）
P0 frozen reference       P0-09 [C] PASS (1698)；bmp_parser PASS (8)
P1-01 adapter             v0.4 [U] PASS(61)；strict arbiter→adapter [C-sub] PASS(42)
P1-02A official core      [C-sub] PASS(24)，tCK/tRCD/App read-DM/physical READ DQM violations 全 0
P1-02B TD integration     [S] PASS：TD5.6.2 SynOpt/PhyOpt/BitGen；150MHz setup/hold 0 violations
P0-01 ~ P0-06             [U]
P0-07 sdram_arbiter       [U] PASS(39)
P0-08 framebuffer chain   —（historical [C-sub]；arbiter v1.1 后仍待单独重跑）
P0-09 full media chain    [C] PASS(1698)
P1-03A video adapter      [U] PASS(24)；line-buffer -> adapter [C-sub] PASS(57)
P1-03B pattern/provider     [U] PASS(37)；APUG092 protected behavior sim=TOOL_BLOCKED；TD elaboration PASS
P1-04A 720p clock experiment SynOpt PASS；75/375MHz setup/hold/removal timing FAIL，不可烧板
P1-04B official-640 board    candidate：working 25/125MHz PLL + HDMI_B real ADC 已导入，待 TD P&R/BitGen/真板
TD SDRAM backend          [S]：6.666ns target，WNS=+0.059ns，TNS=0，hold min slack=+0.260ns
Hardware                  开发板/TF卡/显示器已到位；用户已确认官方 lab_ex4_tf 真板可运行；本项目尚无 [B]/[L]
```

当前 P1-02B `.al` TOP 为 `p1_apug011_td_top`，按 APUG011 官方工程方式加入 `global_def.v`（`GlobalIncluded=true`）、三个独立 protected `.enc.v`、官方 `clk_pll.v`、wrapper/BIST，并只绑定 `constraints/p1_apug011_td.sdc` 这一份**时钟级 synthesis harness 约束**；`ADC_FILE` 为空，board pin 模板不参与本轮。该 harness 使用 APUG011 官方参考的 25 MHz 输入 PLL（150 MHz 0°/180° SDRAM clocks），**不是 HX4S20C 最终 50 MHz board top**。

P1-02B 已在 **TD5.6.2 / V5.6.71036 GUI** 完成最终 closure：SynOpt、PhyOpt(place+route)、BitGen 全部 PASS；150 MHz / 6.666 ns 下 setup errors=0、WNS=+0.059 ns、TNS=0.000 ns、minimum period=6.607 ns、Max Freq=151.355 MHz；hold errors=0、minimum slack=+0.260 ns、TNS=0.000 ns。`EG_PHY_PLL` 与 `EG_PHY_SDRAM_2M_32` 均正常识别/物理实现，后者不是 BRAM。最终资源为 LUT=283、REG=243、LE=377、PLL=1、GCLK=1、BRAM=0、BRAM32K=0。由此 SDRAM backend 子系统正式记 `[S]`；这仍**不代表**最终 HX4S20C board pin build 或真板功能 `[B]`。

## 3. P0 冻结证据

| ID | 对象 | 状态 | 已记录回归证据 |
|---|---|---|---|
| P0-01 | `fat32_file_reader` | `[U]` | fragmented chain / file_size / abnormal FAT cases；18 checks |
| P0-02 | `bmp_pixel_stream` | `[U]` | padding 0/1/2/3、17/640/641、offset gap、异常 header；13393 checks |
| P0-03 | `framebuffer_writer` | `[U]` | stall/FIFO/address/RGB word；1345 checks |
| P0-04 | `frame_buffer_manager` | `[U]` | A/B ownership、frame-boundary swap、failure reuse；166 checks |
| P0-05 | `line_buffer_pingpong` | `[U]` | golden literal + 连续行输出；2204 checks |
| P0-06 | `line_prefetcher` | `[U]` | multi-outstanding、stall、timeout/recovery；2713 checks |
| P0-07 | `sdram_arbiter` | `[U]` | **v1.1 PASS(39)**；timing cleanup 后 unit regression 已恢复 |
| P0-08 | framebuffer + mock SDRAM mini-chain | `—` | historical `[C-sub]` PASS(1495)；arbiter v1.1 后待回归 |
| P0-09 | full P0 media chain | `[C]` | **PASS(1698)**；v1.1 arbiter candidate-1 同轮回归通过 |

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

P0 冻结基线中的 33 个 `src/*.v` 已包含在既有 36/36 回归中。P1-01 新增 `sdram_adapter`，P1-02 加入 `apug011_core_wrapper`、BIST 与 TD harness；当前 TD5.6.2 使用官方 Global Include + 独立 protected-source 组织；vendor protected core/PLL 不计 project-owned 模块状态。当前仿真环境为 **QuestaSim 10.7c**。

2026-09-01 candidate-2 已完成最终回归与 TD closure。六项 RTL 回归全部通过：`sdram_arbiter v1.1` **PASS(39)**、`sdram_adapter v0.4` **PASS(61)**、arbiter→adapter strict chain **PASS(42)**、P0 media chain **PASS(1698)**、P1 BIST **PASS(9)**、P1-02A official protected-core chain **PASS(24)**。随后 TD5.6.2 GUI SynOpt/PhyOpt/BitGen 全部成功，150 MHz / 6.666 ns 最终 **setup errors=0、WNS=+0.059 ns、TNS=0；hold errors=0、min slack=+0.260 ns、TNS=0**。原 baseline 的 9 条 setup failure 已全部消失。

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
| framebuf | `sdram_arbiter` | **P0** | `[U]` | **v1.1 PASS(39)**；candidate-1 timing cleanup 后 unit regression 已恢复 |
| framebuf | `sdram_adapter` | **P1** | `[U]` | **v0.4 PASS(61)**；strict arbiter→adapter chain **[C-sub] PASS(42)** |
| top | `apug011_core_wrapper` | **P1-02A/B** | `[C-sub]` | wrapper 未变；v0.4 adapter 下 official APUG011 chain **PASS(24)** |
| top | `apug011_td_compile_unit` | historical | `—` | **DEPRECATED**；TD6.2 实测证明不应通过 `include` 聚合 protected sources；不进入 `.al` |
| top | `p1_apug011_bist` | **P1-02B support** | `[U]` | **PASS(9)**；backend_ready gate、2W+2R、readback、provider_fault negative case |
| top | `p1_apug011_td_top` | **P1-02B** | `[S]` | TD5.6.2 SynOpt/PhyOpt/BitGen PASS；150MHz setup/hold 0 violations，WNS=+0.059ns |
| top | `apug092_core_wrapper` | **P1-03B** | `—` | **candidate**；官方 protected APUG092 stable wrapper，`DEVICE="EG"` / external RGB video |
| top | `apug092_tx_wrapper` | **P1-03B** | `—` | **candidate**；APUG092 core + 官方 `hdmi_phy_wrapper(DEVICE="EG")`，clock generation 外置 |
| top | `p1_apug092_td_top` | **P1-03B** | `—` | **candidate**；**74.25/371.25MHz 1280×720** 双时钟注入 TD harness，不是 final board top；另预留 1080p compile-time profile |
| top | `p1_hdmi_pll_50m` | **P1-04A support** | `—` | **candidate**；HX4S20C 50MHz → 75MHz pixel + 375MHz serial@90°；divider/phase 已实现，analog fields 待 TD5.6.2 IPC 生成比对 |
| top | `p1_hx4s20c_hdmi_smoke_top` | **P1-04A** | `—` | **candidate**；真实 50MHz board-clock 边界 + 720p 色条 + APUG092/EG PHY；不使用 KEY1/KEY2，board ADC 尚未绑定 |
| display | `hdmi_video_adapter` | **P1-03A** | `—` | **candidate**；APUG092 video contract bridge，unit + line-buffer sub-chain TB 已写好，待统一回归后升 `[U]`/`[C-sub]` |
| display | `hdmi_test_pattern_line_provider` | **P1-03B support** | `—` | **candidate**；可综合 8 色条 whole-line provider，用于隔离 SDRAM 的 HDMI bring-up |
| display | `vga_timing` | P1/P2 support | `[U]` | timing/test source；正式 HDMI 由 APUG092 内部 Video Source/phase matching 负责 |
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
| `tb_framebuffer_mock_chain` | `—` | historical P0-08 PASS；arbiter v1.1 后待回归 |
| `tb_p0_media_chain` | `[C]` | **PASS(1698)**；v1.1 arbiter candidate-1 同轮回归通过 |
| `tb_sdram_adapter` | `[U]` | **v0.4 PASS(61)** |
| `tb_sdram_arbiter_adapter_chain` | `[C-sub]` | **v0.4 adapter PASS(42)** |
| `tb_sdram_adapter_apug011_official` | `[C-sub]` | **v0.4 adapter + official APUG011 PASS(24)** |
| `tb_p1_apug011_bist` | `[U]` | **PASS(9)**；backend_ready/2W+2R/readback/provider_fault |

## 5. P1 计划与状态

P1 目标是把 P0 的抽象接口接到官方 IP、TD 和真板，不重复实现厂商已有协议层。

| ID | 任务 | 目标证据 | 当前 |
|---|---|---|---|
| P1-01 | `sdram_adapter` 对接 APUG011 application-side；4-word micro-group / mask / response-filter | adapter `[U]` + arbiter-memory sub-chain `[C-sub]` | **v0.4 [U] PASS(61) + strict chain [C-sub] PASS(42)** |
| P1-02 | APUG011 官方 protected core + TD 集成 | official-core `[C-sub]`，随后 TD `[S]` | **完成：P1-02A [C-sub] PASS(24)；P1-02B [S]，150MHz setup/hold 0 violations** |
| P1-03 | `hdmi_video_adapter` + APUG092 EG wrapper/PHY；验证整行连续 | adapter `[U]` + video sub-chain `[C-sub]` + vendor synthesis boundary | **adapter [U] PASS(24)；line-buffer sub-chain [C-sub] PASS(57)；pattern [U] PASS(37)；protected Questa=TOOL_BLOCKED；TD elaboration PASS** |
| P1-04 | board-safe HDMI top / PLL / **官方 HX4S20C ADC/SDC** | color-bar build `[S]`，随后真板 `[B]` | **P1-04A 720p STA FAIL；P1-04B 已实现 working-official 25/125MHz + 640x480 + HDMI_B real ADC，待 P&R/BitGen/board** |
| P1-05 | 将已收口 SDRAM/line-buffer 接入 board HDMI；先 640×480 与官方基线等分辨率出图，再独立提升 720p | `[B]` | `—` |
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

最终 candidate-2 回归：P0-09 **PASS(1698)**、`sdram_adapter v0.4 PASS(61)`、strict arbiter-adapter chain **PASS(42)**，并完成 P1 BIST PASS(9) 与 official APUG011 PASS(24)。P0 `[C]` 和 P1-01 `[U]/[C-sub]` 均保持有效。

P1-02 按两个证据边界正式收口：

- **P1-02A `[C-sub]`**：`sdram_adapter v0.4 -> official protected APUG011 -> official IS42 model` 回归 **PASS(24)**；tCK/tRCD/App read-DM/physical READ DQM violations 全 0，addr5/addr8 正确读回。125 MHz/180° 仅是 IS42 -7 model-safe 行为仿真设置，不改变硬件 150 MHz 目标。
- **P1-02B `[S]`**：TD5.6.2 / V5.6.71036 GUI 完成 SynOpt + PhyOpt(place+route) + BitGen。150 MHz / 6.666 ns 下 **setup errors=0、WNS=+0.059 ns、TNS=0.000 ns；hold errors=0、min slack=+0.260 ns、TNS=0.000 ns；minimum period=6.607 ns、Max Freq=151.355 MHz**。原始 baseline 9 条 setup failure 已全部消失。资源：LUT=283、REG=243、LE=377、PLL=1、GCLK=1、BRAM=0、BRAM32K=0。`EG_PHY_PLL` 与 `EG_PHY_SDRAM_2M_32` 均正常实现，BitGen 生成合法 `.bit`。

最终 worst setup path 已为正 slack：`u_adapter/provider_fault_reg_syn_12.clk -> u_bist/reg1_syn_28`，slack +0.059 ns；不再存在负 timing path。CLI `import_device -package` 空 DB 的失败只记录为 TD5.6.2 CLI 环境问题，不覆盖 GUI implementation 的 `[S]` 证据。详细 closure 记录见 `docs/develop_records/P1-02B_TD56_TIMING_CLOSURE_CANDIDATE2.md`。

P1 完成前最重要的资源检查：`line_buffer_pingpong` 的 RAM 数组故意不做整块 reset，以保留 ERAM inference 机会；只有 TD 报告确认后才能说“行缓存进了 ERAM”。


### P1-03A / P1-03B 本轮验证结果

QuestaSim 10.7c 已完成 project-owned HDMI 路径验证：

```text
hdmi_video_adapter                     [U]     PASS(24)
line_buffer_pingpong -> video adapter  [C-sub] PASS(57)
hdmi_test_pattern_line_provider        [U]     PASS(37)
```

对应 transcript 已保存到 `docs/evidence/`。adapter 行边界 ready / 行内连续 / `axis_user` / `axis_last` 契约已由 TB 主动检查。

APUG092 protected behavioral simulation 的 `vlog` 阶段 Errors=0、Warnings=80（均为 protected source `vlog-2600`），但 `vsim` optimization 在 protected region 报错 4 次并停止。因此该项记录为 **TOOL_BLOCKED**，不降低 project-owned RTL 的 `[U]/[C-sub]` 状态。TD5.6.2 SynOpt 已能正常 elaboration protected APUG092、EG PHY 与四路 `EG_LOGIC_ODDR`，synthesis integration 边界成立。

### P1-04A 720p clock experiment 结论

P1-04A 的 50MHz -> 75MHz pixel / 375MHz serial@90deg 被 TD 正确派生，SynOpt/ gate DB 成功；但 STA 不闭合：

```text
375 MHz setup : 3 errors, WNS=-0.122 ns, TNS=-3.660 ns
75 MHz hold    : 10 errors, WNS=-0.102 ns, TNS=-66.601 ns
removal        : 3 errors, WNS=-0.164 ns
```

因此 P1-04A 不是 `[S]`，也不是 board-safe build。它保留为 720p 性能实验，禁止下载到板。

### P1-04B official-640 board-safe candidate

用户已在实际 HX4S20C + TF卡 + HDMI显示器上确认官方 `lab_ex4_tf` 正常运行。只读抽取得到：50MHz board clock、HDMI_B 真实 pin、640x480 timing、25/125MHz working PLL 完整参数。P1-04B 已按这些事实新增：

- `src/top/p1_hdmi_pll_50m_25_125.v`：官方 working PLL 参数；
- `src/top/p1_hx4s20c_hdmi_board_top.v`：640x480 八色条 board top；
- `constraints/p1_hx4s20c_hdmi_board.sdc`；
- `constraints/p1_hx4s20c_hdmi_board.adc`：R7/G5/F1/E1/C3/P2/R2 实际映射；
- `FPGA_Competition_HDMI_P1-04B.al`：TD5.6.2 独立 board build。

该 top 不使用 KEY1/KEY2，也不引出未验证 LED debug pins。当前状态仍是 **candidate**：必须完成 TD5.6.2 SynOpt + PhyOpt + timing + BitGen 后才允许下载；真显示器稳定彩条通过后才能记 `[B]`。

分辨率政策：P1-04B 640x480 与 working 官方样例相同，满足“不低于官方样例”的 bring-up 下限；720p 仍是后续性能目标，但必须从 P1-04A 的 timing fail 出发重新做 PLL/STA closure，而不是边猜 board pin 边提频。1080p/双板继续留在 P4 feasibility。

详细见 `docs/develop_records/P1-04B_HX4S20C_OFFICIAL640_BOARD_SAFE_CANDIDATE.md`。

## 6. P2~P4 计划

| 阶段 | 重点 | 当前基础 | 阶段完成条件 |
|---|---|---|---|
| P2 | HDMI audio、OSD/状态栏、亮度/对比度、转场、音频柱、应急 UI、交互整合 | 相关组件多数 `[U]` | presentation 子链 `[C]` + 真板 `[B]` |
| P3 | YUV444 `.vseq` 短视频；frame scheduling；color-space + scaler | reader/unpack/color/scaler `[U]` | 视频端到端 `[C]` + 真板 `[B]` |
| P4 | YUV420、SDIO、1080p/双板链路、其他加分 | yuv420 组件 `[U]`；1080p 仅参数预留 | 不阻塞主作品；先测 EG HDMI PHY 上限再决定是否重构 |

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
| 约束错误 | P1-04B 只使用 working official lab_ex4_tf 的 HX4S20C HDMI_B pin/clock；历史模板仍禁止烧板 |
| SD 真卡差异 | 真卡 `[B]` 前不把 SD reader `[U]` 宣传成已板级可用 |
| 功能膨胀 | P1 完成前不新增复杂特效；P4 不阻塞主线 |
| 文档漂移 | 只维护本文件的状态表；详细行为以 RTL/TB 为源 |
