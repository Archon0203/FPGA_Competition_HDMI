# 35 · P0 Implementation Freeze v1.0

> 冻结日期：2026-08-31  
> 状态：**P0 media chain `[C] CHAIN PASS`**

## 1. 最终状态

```text
P0-01 fat32_file_reader       [U]
P0-02 bmp_pixel_stream        [U]
P0-03 framebuffer_writer      [U]
P0-04 frame_buffer_manager    [U]
P0-05 line_buffer_pingpong    [U]
P0-06 line_prefetcher         [U]
P0-07 sdram_arbiter           [U]
P0-08 framebuffer/mock chain  [C-sub]
P0-09 full P0 media chain     [C]
```

当前工程共有 **36 个 `tb_*.v`，36/36 ModelSim PASS**。

## 2. P0-09 冻结证据

```text
CASE-GOLDEN + CASE0~CASE3 全部通过
PASS: P0 media chain end-to-end all cases passed (checks=1698)
```

关键实测：

- CASE0：fragmented FAT `3→7`，17×12，文件 >512B，padding=1；最终全部 RGB 与 independent golden 一致。
- 波形首像素：`lb_pixel_data=0x125492 == expected_rgb(0x12,0,0)`。
- CASE1：640×2，8 个非连续 cluster，≥7 次 FAT traversal、≥8 个 data-cluster read；640-pixel active line 无 valid gap。
- CASE2：无 reset 第三文件，`data_offset=70` + `0xEE` gap；gap 不进入 pixel stream，A/B buffer 再切换。
- CASE3：arbiter/mock/linebuffer/prefetch 全部终态 clean；读写命令均 >1400。

## 3. 冻结边界

P0 冻结的是**业务数据流与抽象内存边界**：

```text
FAT32 -> BMP -> RGB888 -> framebuffer
 -> sdram_arbiter -> [SDRAM backend boundary]
 -> line prefetch -> ping-pong line buffer -> display-order RGB888
```

P0 不冻结厂商物理实现细节。P1 允许新增/完善：

```text
sdram_adapter -> APUG011 -> EG4S20 internal SDRAM
hdmi_video_adapter -> APUG092 -> HDMI PHY
hdmi_audio_adapter -> APUG092 audio
system_top / hx4s20c_top / PLL / constraints
```

但这些 P1 工作**不得反向改变 P0 主链契约**，除非出现官方资料/TD/真板证据并完成 Architecture Change Request。

## 4. 状态边界

`[C]` 明确不表示：

- APUG011 已接通；
- TD synthesis/P&R/timing 已通过；
- ERAM/SDRAM inference 已核对；
- HDMI 已出图；
- 真 TF 卡已通过；
- 板级长稳已通过。

这些分别属于后续 `[S]` / `[B]` / `[L]`。

## 5. P1 起点

P1 首要顺序：

```text
P1-01 sdram_adapter ↔ APUG011
P1-02 TD synthesis/P&R + timing/resource/RAM inference
P1-03 hdmi_video_adapter ↔ APUG092
P1-04 system_top / hx4s20c_top / official constraints
P1-05 hardware SDRAM + HDMI board validation
```

P0 从本文件起进入维护模式，不再新增功能。
