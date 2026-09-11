# constraints — 管脚与时钟/时序约束

> **必须**来自官方板卡资料网盘（提取码 `M5N1`）与 `lab_ex` 工程，并逐条与 HX4S20C 原理图核对。
> 此目录**禁止用 AI 凭空生成**引脚号，否则极易烧录失败/烧到非预期 IO。

| 文件 | 说明 |
|---|---|
| `*.cst` / `*.lpf` | 管脚/位置约束（HDMI 差分、SD/SDRAM、按键、拨码、数码管、LED、蜂鸣器、UART） |
| `*.sdc` | 时钟/时序约束（50M 系统、P1-03B 74.25M 像素、371.25M APUG092 serial=5×pixel、150M SDRAM 等） |

> 历史 `.cst`/`.adc.template` 仍是占位；`p1_hx4s20c_hdmi_board.adc` 是例外，它已由用户 working official lab_ex4_tf 真板工程逐项确认。


## P1 专用 harness

- `p1_apug011_td.sdc`：已验证 P1-02B SDRAM backend harness。
- `p1_apug092_td.sdc`：P1-03B candidate；两路 top-level injected clocks（**74.25/371.25 MHz**），无 board pin。官方 APUG092 随包示例是 PH1A，因此其 PLL/pin.adc 不复制到 EG4S20。

P1-04A 的 `p1_hx4s20c_hdmi_smoke.sdc` + `.adc.template` 只属于失败的 720p timing experiment，不可烧板。

P1-04B 已新增：
- `p1_hx4s20c_hdmi_board.sdc`：50MHz input + `derive_pll_clocks`，目标 working 25/125MHz；
- `p1_hx4s20c_hdmi_board.adc`：从用户实际运行成功的 official `lab_ex4_tf` 提取的 HX4S20C HDMI_B pin/IOSTANDARD。

P1-04B ADC 是当前唯一允许用于首次 HDMI BitGen/board smoke test 的 HDMI board constraint。KEY1/KEY2 不在该工程中。
