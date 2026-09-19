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
- `derive_pll_clocks`；
- TD5.6.2 实际 generated-clock 名称：25 MHz `u_hdmi_pll/u_pll.clkc[0]`、150 MHz `u_sdram_pll/pll_inst.clkc[1]`；
- 25 MHz pixel 与 150 MHz SDRAM 声明为 asynchronous groups，只通过项目内显式 FIFO/synchronizer 跨域；
- 不对 150 MHz same-domain timing 使用 false path。

P1-05A final combined STA：0 setup / 0 hold，WNS `+0.068 ns`，WHS `+0.131 ns`。由于余量较薄，active RTL/SDC 任何修改后都必须重新实现和检查 timing report。

其他 SDC/ADC 为历史或实验文件，不代表当前 active build。
