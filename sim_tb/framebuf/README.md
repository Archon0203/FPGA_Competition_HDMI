# sim_tb/framebuf

framebuffer / SDRAM / CDC testbench。

P1-05A final：

```text
run_p1_framebuffer_pattern_writer.do             PASS(259)
run_p1_sdram_read_cdc_bridge.do                  PASS(13)
run_p1_sdram_cached_adapter.do                   PASS(58)
run_p1_sdram_cached_adapter_apug011_official.do  PASS(24)
```

cached adapter unit 最终计数：`abstract_reads=8, app_reads=8, hits=6, misses=2`。
official APUG011 compatibility 最终 read count：`accepted=2, hits=0, misses=2, app_reads=8`，读回数据正确。

运行示例：

```powershell
cd sim_work
vsim -c -do ../sim_tb/framebuf/run_p1_sdram_cached_adapter.do
```

详细状态以 `docs/03_plan_and_status.md` 为准。
