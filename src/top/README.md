# top

## HDMI golden rollback

```text
p1_hx4s20c_hdmi_board_top.v
```

P1-04C `[B] PASS`，固定八色条。HDMI 无信号时优先回退该 top。

## 当前 active top

```text
p1_hx4s20c_sdram_hdmi_top.v
```

P1-05A 当前 TD6.2.1 routed `[S] PASS`；历史真板 `[B] PASS`，TD6.2.1 bitstream 尚待重新上板复测：

- 保留 P1-04C HDMI PLL / reset / EDID / APUG092 / EG PHY / pin；
- 增加 official APUG011 PLL（25→150/shifted）；
- 固定 framebuffer pattern 写入 internal SDRAM；
- explicit 25↔150 MHz read CDC；
- `p1_sdram_cached_adapter` 支撑 sequential video bandwidth；
- line prefetch / ping-pong scanout；
- 只在 safe frame boundary 把 RGB data 从 golden bars 切换到 SDRAM。

TD6.2.1 final STA 为 0 setup/hold，SWNS `+0.599 ns`、HWNS `+0.003 ns`；BitGen 已生成 bitstream。当前文档不把本轮 TD6.2.1 build 写成新的真板通过证据。

## Vendor wrapper

- `apug011_core_wrapper.v`：APUG011 thin wrapper；
- `apug092_core_wrapper.v` / `apug092_tx_wrapper.v`：HDMI vendor boundary；
- vendor protected source 只读，不修改。
