# Project IP configuration

`ip/` 保留可编辑的 Anlogic IP Generator 输入和实验配置。

- `p1_hdmi_pll_50m_75_375.ipc`：P1-04A 720p 实验，50 MHz → 75/375 MHz；该配置对应的历史实现 STA FAIL，**不是当前 board PLL**。
- 当前 P1-04C working board PLL 由 `src/top/p1_hdmi_pll_50m_25_125.v` 固化官方 `lab_ex4_tf` 已验证参数：50 MHz → 25/125 MHz，真板 `[B] PASS`。

后续重新做 720p 时，应在独立实验中通过 TD5.6.2 IP Generator/PLL 报告核对全部 divider/phase/analog tuning，并取得 timing + board 证据后才可替换 golden PLL。
