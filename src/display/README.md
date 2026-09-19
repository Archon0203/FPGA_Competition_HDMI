# display

显示处理与 HDMI application-side RTL。

## P1-04C golden

`hdmi_official_baseline_source.v` 是 board-proven free-running 640×480 source。P1-05A 保留它产生 `axis_user/axis_valid/axis_last`，只在安全 frame boundary 替换 RGB `axis_data`。

## P1-05A `hdmi_framebuffer_scanout.v`

职责：与 P1-04C 800×525 raster 同相运行、调度 `line_buffer_pingpong.read_start`、对齐 active-video cadence、提供 frame boundary 并检测相位错误。

验证：`[U] PASS(35)`；最终 P1-05A framebuffer 真板稳定显示，无可见 scanline underflow/tearing/jitter。

`hdmi_video_adapter.v` 仍保留 `[U] PASS(24)` 的历史证据，但 P1-05A 不让它接管 APUG092 golden cadence。
