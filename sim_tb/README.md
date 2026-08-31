# sim_tb — 仿真测试台源码（按模块分类）

testbench 源码按 `src/` 的子目录**一一对应**存放。ModelSim 运行产物放在 **`sim_work/`**（gitignore）。

```
sim_tb/
├─ top/        # tb for 顶层/时钟/复位
├─ storage/    # sd_spi / sd_reader / fat32_scan / fat32_file_reader / bmp_parser / bmp_pixel_stream / vseq_reader / vseq_yuv_unpack
├─ framebuf/   # async_fifo / framebuffer_writer / manager / prefetch / line buffer / arbiter / adapter
├─ display/    # vga_timing / image_enhance / color_space / image_scaler / transition / osd_overlay / tmds_encoder
├─ audio/      # tone_gen / audio_visual / hdmi_audio_pack(educational) / hdmi_audio_adapter
├─ interact/   # key_filter / sw_filter / menu_fsm / seg_driver / dual_led / beep
└─ app/        # app_scenario
```

约定：`tb_<模块>.v` 与 `run_<模块>.do`（编译+运行）放在同一个子目录。

**运行方式**（在 `sim_work` 目录）：
```powershell
cd sim_work
vsim -c -do ../sim_tb/display/run_vga_timing.do
```



## 当前回归口径（2026-08-31）

- 当前共有 **36 个 `tb_*.v`，全部 ModelSim PASS**；P0-07 `[U]`、P0-08 `[C-sub]`、P0-09 完整媒体主链 `[C]`。
- `tb_fat32_file_reader`：CASE0~CASE8 PASS（checks=18），模块 `[U]`。
- `tb_bmp_pixel_stream`：CASE0~CASE13 PASS（checks=13393），模块 `[U]`。
- 单模块 `[U]` 不等于链路 `[C]`；当前 P0-09 已用完整 FAT32/BMP/framebuffer/mock/display 回归取得 `[C]`。

- P0-05 `tb_line_buffer_pingpong`：CASE-GOLDEN+CASE0~CASE8 PASS（checks=2204）。
- P0-06 `tb_line_prefetcher`：CASE0~CASE13 PASS（checks=2713）。
