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

### P1-05B media write-side loader

```text
fragmented FAT32 sector provider
 -> p1_media_framebuffer_loader
 -> sdram_arbiter
 -> p1_sdram_cached_adapter
 -> mock APUG011 application port
```

`run_p1_media_framebuffer_loader.do` 已 `PASS(225)`，验证真实 BMP 的 BGR/bottom-up/padding/fat-fragmentation 语义、非法 signature 拒绝，最终写到 cached APUG011 provider memory。该测试只覆盖写入侧，不改变或替代 P1-05A HDMI/read path。
