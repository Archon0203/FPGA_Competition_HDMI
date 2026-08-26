# src/top
- `top.v`：顶层例化、模块间走线、IO 引脚映射（引脚号见 `constraints/`）。
- `clk_gen.v`：用板载 50MHz + PLL 生成 `clk_sys`/`clk_pix`/`clk_tmds`/`clk_sdram`/`clk_sdo`/`clk_aud`。
- `reset_gen.v`：上电复位与各时钟域同步复位。

