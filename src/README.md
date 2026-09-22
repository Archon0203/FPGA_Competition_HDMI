# src

当前源码同时保留：

- P0 已冻结 media-core RTL；
- P1-02 APUG011 SDRAM backend；
- P1-04C HDMI board golden rollback；
- **P1-05A SDRAM framebuffer→HDMI：TD6.2.1 routed `[S] PASS`，历史真板 `[B] PASS`**。

当前 active TD TOP：

```text
p1_hx4s20c_sdram_hdmi_top
```

HDMI rollback TOP：

```text
p1_hx4s20c_hdmi_board_top   # P1-04C [B] PASS
```

目录：

```text
storage/    TF/FAT32/BMP/VSEQ
audio/      audio path
framebuf/   framebuffer / SDRAM / cached adapter / CDC / line buffer
display/    HDMI-facing source/scanout/process
top/        board top / PLL / vendor wrapper
interact/
app/
vendor/     Anlogic official/protected source, read-only
```

P1-05B 默认复用 P1-05A 的 SDRAM→HDMI display baseline，只在上游接入 TF/FAT32/BMP。状态与冻结边界以 `docs/03_plan_and_status.md` 为准。
