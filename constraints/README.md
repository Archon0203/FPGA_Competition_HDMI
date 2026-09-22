# constraints

当前 active P1-05A board build 复用 P1-04C 已真板验证的 HDMI_B ADC，并在 SDC 中增加 P1-05A CDC timing boundary：

```text
ADC: p1_hx4s20c_hdmi_board.adc
SDC: p1_hx4s20c_hdmi_board.sdc
```

ADC：

| port | pin | standard |
|---|---|---|
| clk | R7 | LVCMOS33 |
| HDMI_D0_P | G5 | LVDS33 |
| HDMI_D1_P | F1 | LVDS33 |
| HDMI_D2_P | E1 | LVDS33 |
| HDMI_CLK_P | C3 | LVDS33 |
| HDMI_DDC_SCL | P2 | LVCMOS33 |
| HDMI_DDC_SDA | R2 | LVCMOS33 |

SDC：

- 50 MHz board root clock；
- `derive_clocks`（TD6.2.1 推荐命令；旧 `derive_pll_clocks` 仅见于历史/实验约束）；
- TD6.2.1 final report 中的 generated-clock 名称：25 MHz `u_hdmi_pll/u_pll.clkc[0]`、150 MHz `u_sdram_pll/pll_inst.clkc[1]`；
- 25 MHz pixel 与 150 MHz SDRAM 声明为 asynchronous groups，只通过项目内显式 FIFO/synchronizer 跨域；
- 不对 150 MHz same-domain timing 使用 false path。

当前 TD6.2.1 final routed STA：0 setup / 0 hold，SWNS `+0.599 ns`、HWNS `+0.003 ns`，coverage `99.17%`。硬件最小裕量仅 3 ps，active RTL/SDC 任何修改后都必须重新实现和检查 timing report。当前 run 仍有两个 SDRAM location warning 和一条 local clock routing warning。

其他 SDC/ADC 为历史或实验文件，不代表当前 active build。
