# sim_tb — 仿真测试台源码（按模块分类）

testbench 源码按 `src/` 的子目录**一一对应**存放。ModelSim 运行产物放在 **`sim_work/`**（gitignore）。

```
sim_tb/
├─ top/        # tb for 顶层/时钟/复位
├─ storage/    # sd_spi / sd_reader / fat32_scan / bmp_parser / vseq_reader
├─ framebuf/   # sdram_ctrl / frame_buffer / async_fifo
├─ display/    # vga_timing / image_enhance / color_space / image_scaler / transition / osd_overlay / tmds_encoder
├─ audio/      # hdmi_audio / tone_gen
├─ interact/   # key_filter / sw_filter / menu_fsm / seg_driver / dual_led / beep
└─ app/        # app_scenario
```

约定：`tb_<模块>.v` 与 `run_<模块>.do`（编译+运行）放在同一个子目录。

**运行方式**（在 `sim_work` 目录）：
```powershell
cd sim_work
vsim -c -do ../sim_tb/display/run_vga_timing.do
```

