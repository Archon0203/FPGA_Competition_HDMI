# integration testbenches

## P0 full media chain

```text
vsim -c -do ../sim_tb/integration/run_p0_media_chain.do
```

范围：

`fat32_file_reader -> bmp_parser/bmp_pixel_stream -> framebuffer -> mock SDRAM -> line prefetch/buffer -> display RGB`

实测：CASE-GOLDEN+CASE0~CASE3 全部 PASS（checks=1698）。完整 P0 media chain 已标 `[C]`；本 TB 作为 P0 冻结回归保留。

## P1 HDMI candidates

```text
vsim -c -do ../sim_tb/integration/run_hdmi_video_linebuffer_chain.do
```

P1-03A：真实 `line_buffer_pingpong -> hdmi_video_adapter` project-owned 子链；candidate，待回归。

```text
vsim -c -do ../sim_tb/integration/run_apug092_external_video_core.do
```

P1-03B：`color-bar provider -> hdmi_video_adapter -> official protected APUG092`，停在并行 10-bit TMDS words，避免依赖 EG ODDR 仿真模型；candidate，待回归。
