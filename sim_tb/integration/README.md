# integration testbenches

## 已验证链路

### P0 full media chain

`run_p0_media_chain.do` → `[C] PASS(1698)`。

### line buffer → HDMI adapter

`run_hdmi_video_linebuffer_chain.do` → `[C-sub] PASS(57)`。

### APUG092 protected behavior

QuestaSim 10.7c 对 protected region 的 behavior simulation 仍 TOOL_BLOCKED；P1-04C/P1-05A 已用 TD + 真板越过该工具限制。

### P1-05A SDRAM → HDMI pipeline

`run_p1_sdram_hdmi_pipeline.do` → `PASS(258)`。

### P1-05A cached-provider chain

```text
p1_sdram_hdmi_pipeline
 -> sdram_arbiter
 -> p1_sdram_cached_adapter
 -> mock_apug011_app_port
```

`run_p1_sdram_hdmi_cached_chain.do` → `PASS(260), pixels=256, app_reads=328, hits=243, misses=82, underflow=0`。

该链补上理想 one-cycle memory TB 无法覆盖的 provider latency / 4-word grouping / sustained-bandwidth 场景，是 P1-05A 真板消除移动扫描线 underflow 的关键 regression。
