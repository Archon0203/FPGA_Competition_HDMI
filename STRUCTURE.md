# 项目目录结构

当前 active baseline 为 **P1-05A internal SDRAM framebuffer → HDMI_B `[S][B] PASS / CLOSED`**。P1-04C 八色条 top 继续保留为 HDMI golden rollback。

根目录只使用一个 TD 工程：

```text
FPGA_Competition_HDMI.al
```

```text
FPGA_Competition_HDMI/
├─ FPGA_Competition_HDMI.al
├─ README.md
├─ STRUCTURE.md
├─ CONTRIBUTING.md
├─ docs/
│  ├─ 01_architecture.md             # 当前架构权威
│  ├─ 02_implementation_goals.md     # 目标与验收边界
│  ├─ 03_plan_and_status.md          # 唯一进度/状态权威
│  ├─ 04_use_cases.md                # 场景与演示口径
│  ├─ develop_records/               # 开发过程记录，可追加，不替代 01~04
│  │  └─ P1-05A_CLOSEOUT_20260912.md # 本阶段实现/调试/timing 复盘
│  ├─ evidence/                      # 历史验证证据
│  └─ olds/                          # 历史主文档，只读
├─ src/
│  ├─ top/
│  │  ├─ p1_hx4s20c_hdmi_board_top.v      # P1-04C HDMI rollback top
│  │  └─ p1_hx4s20c_sdram_hdmi_top.v      # P1-05A active top
│  ├─ framebuf/
│  │  ├─ async_fifo.v
│  │  ├─ sdram_arbiter.v
│  │  ├─ sdram_adapter.v                   # P1-02 frozen random-word adapter
│  │  ├─ p1_sdram_cached_adapter.v         # P1-05 sequential video adapter
│  │  ├─ line_prefetcher.v
│  │  ├─ line_buffer_pingpong.v
│  │  ├─ p1_framebuffer_pattern_writer.v
│  │  ├─ p1_sdram_read_cdc_bridge.v
│  │  └─ p1_sdram_hdmi_pipeline.v
│  ├─ display/
│  │  ├─ hdmi_official_baseline_source.v
│  │  └─ hdmi_framebuffer_scanout.v
│  ├─ storage/
│  ├─ audio/
│  ├─ interact/
│  ├─ app/
│  └─ vendor/anlogic/                      # vendor/protected source，只读
├─ constraints/
│  ├─ p1_hx4s20c_hdmi_board.adc
│  ├─ p1_hx4s20c_hdmi_board.sdc
│  └─ ...                                  # 历史/实验约束
├─ sim_tb/
│  ├─ framebuf/
│  ├─ display/
│  └─ integration/
├─ ip/
├─ tools/
└─ data/                                   # 默认不入仓库
```

## Active TD build

```text
TOP = p1_hx4s20c_sdram_hdmi_top
```

```text
50 MHz
├─ HDMI PLL -> 25 / 125 MHz
│   └─ P1-04C APUG092 / HDMI_B golden boundary
│
└─ 25 MHz -> APUG011 PLL -> 150 / shifted SDRAM clocks
    ├─ p1_framebuffer_pattern_writer
    ├─ sdram_arbiter
    ├─ p1_sdram_cached_adapter
    ├─ official APUG011
    └─ EG_PHY_SDRAM_2M_32
           ↓
       ordered read CDC
           ↓ 25 MHz
       line_prefetcher
           ↓
       line_buffer_pingpong
           ↓
       hdmi_framebuffer_scanout
```

APUG092 的 `axis_user/axis_valid/axis_last` 仍来自 P1-04C free-running source；P1-05A 仅在安全 frame boundary 将 `axis_data` 切换为 SDRAM RGB。

## 当前约束

`constraints/p1_hx4s20c_hdmi_board.sdc`：

- 50 MHz root clock；
- `derive_pll_clocks`；
- 25 MHz pixel 与 150 MHz SDRAM 明确声明为异步 clock groups，仅通过既有 CDC FIFO/synchronizer 通信。

最终 combined STA：0 setup / 0 hold，WNS `+0.068 ns`，WHS `+0.131 ns`。该裕量较薄，任何 active RTL/SDC 修改后必须重新实现和 STA。

## Board pin

| Logical port | Pin | Standard |
|---|---|---|
| `clk` | R7 | LVCMOS33 |
| `HDMI_D0_P` | G5 | LVDS33 |
| `HDMI_D1_P` | F1 | LVDS33 |
| `HDMI_D2_P` | E1 | LVDS33 |
| `HDMI_CLK_P` | C3 | LVDS33 |
| `HDMI_DDC_SCL` | P2 | LVCMOS33 |
| `HDMI_DDC_SDA` | R2 | LVCMOS33 |

P1-05A 没有增加 external board pin。

## 文档组织规则

主要当前文档固定为根 `README.md`、`STRUCTURE.md` 与 `docs/01~04`。开发过程记录允许追加到 `docs/develop_records/`，但不能成为状态权威；状态冲突时始终以 `docs/03_plan_and_status.md` 为准。`docs/olds/` 不再更新。
