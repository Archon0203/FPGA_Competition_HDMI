# src/top

当前 P1 顶层/vendor integration 模块：

- `reset_gen.v`：通用复位同步模块，已有历史 `[U]` 证据。
- `apug011_core_wrapper.v`：P1-02 APUG011 stable wrapper。
- `p1_apug011_bist.v`：P1-02 TD BIST，`[U] PASS(9)`。
- `p1_apug011_td_top.v`：P1-02B TD harness，已 `[S]` 收口。
- `apug092_core_wrapper.v`：**P1-03B candidate**，官方 protected APUG092 的稳定 project wrapper；保留 video/audio/ACR/EDID 接口。
- `apug092_tx_wrapper.v`：**P1-03B candidate**，APUG092 core + 官方 `hdmi_phy_wrapper(DEVICE="EG")`。
- `p1_apug092_td_top.v`：**P1-03B candidate**，用外部注入 pixel/serial clocks 的 TD-only 色条 HDMI harness。
- `p1_hdmi_pll_50m.v`：**P1-04A candidate**，EG4S20 50MHz→75MHz pixel/375MHz serial@90° clock wrapper；附 IPC 待 TD5.6.2 生成比对。
- `p1_hx4s20c_hdmi_smoke_top.v`：**P1-04A candidate**，真实 board-clock 边界的 1280×720 色条 smoke top。

工程文件：

- `FPGA_Competition_HDMI.al`：保留 P1-02B 已验证工程。
- `FPGA_Competition_HDMI_P1-03B.al`：当前 APUG092/EG-PHY clock-injected 候选工程；不含板级 ADC。
- `FPGA_Competition_HDMI_P1-04A.al`：50MHz board-clock + EG PLL + APUG092/EG-PHY 色条候选工程；仍不含真实板级 ADC。

P1-04A 已实现 HX4S20C 50 MHz → EG PLL 与 board-oriented HDMI smoke top；P1-04B 再从用户实测通过的 official `lab_ex4_tf` 工程导入 HDMI/DDC/clock pin binding。当前不猜 package pin。PLL divider/phase topology 已实现，但 analog tuning 仍必须由 TD5.6.2 IPC 生成结果复核。
