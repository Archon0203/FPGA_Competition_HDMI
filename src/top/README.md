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

P1-05A 已 `[S][B] PASS / CLOSED`：

- 保留 P1-04C HDMI PLL / reset / EDID / APUG092 / EG PHY / pin；
- 增加 official APUG011 PLL（25→150/shifted）；
- 固定 framebuffer pattern 写入 internal SDRAM；
- explicit 25↔150 MHz read CDC；
- `p1_sdram_cached_adapter` 支撑 sequential video bandwidth；
- line prefetch / ping-pong scanout；
- 只在 safe frame boundary 把 RGB data 从 golden bars 切换到 SDRAM。

最终 combined STA 0 setup/hold，WNS `+0.068 ns`；最终 bitstream 真板稳定显示完整 framebuffer。

## Vendor wrapper

- `apug011_core_wrapper.v`：APUG011 thin wrapper；
- `apug092_core_wrapper.v` / `apug092_tx_wrapper.v`：HDMI vendor boundary；
- vendor protected source 只读，不修改。
