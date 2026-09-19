# sim_tb

Questa testbench 与统一 `run_*.do` 入口。建议从独立 `sim_work` 目录执行。

## P1-05A final results

```text
p1_framebuffer_pattern_writer      PASS(259)
p1_sdram_read_cdc_bridge           PASS(13)
hdmi_framebuffer_scanout           PASS(35)
p1_sdram_hdmi_pipeline             PASS(258)
p1_sdram_cached_adapter            PASS(58)
p1_sdram_hdmi_cached_chain         PASS(260), pixels=256, underflow=0
cached adapter + official APUG011  PASS(24)
```

核心命令：

```powershell
vsim -c -do ../sim_tb/framebuf/run_p1_framebuffer_pattern_writer.do
vsim -c -do ../sim_tb/framebuf/run_p1_sdram_read_cdc_bridge.do
vsim -c -do ../sim_tb/display/run_hdmi_framebuffer_scanout.do
vsim -c -do ../sim_tb/integration/run_p1_sdram_hdmi_pipeline.do
vsim -c -do ../sim_tb/framebuf/run_p1_sdram_cached_adapter.do
vsim -c -do ../sim_tb/integration/run_p1_sdram_hdmi_cached_chain.do
vsim -c -do ../sim_tb/framebuf/run_p1_sdram_cached_adapter_apug011_official.do
```

official APUG011 TB 采用 bundled IS42 `-7` model-safe 125 MHz / shifted-clock configuration，验证 application-port grouping/data/timing envelope；最终 150 MHz 硬件频率由 TD5.6.2 STA 与真板负责证明。

状态以 `docs/03_plan_and_status.md` 为准。
