# sim_tb/display
显示处理流水线的 testbench。对应 `src/display`：

```
tb_vga_timing.v     + run_vga_timing.do
tb_image_enhance.v  + run_image_enhance.do
tb_color_space.v    + run_color_space.do
tb_yuv420_upsample.v + run_yuv420_upsample.do
tb_image_scaler.v   + run_image_scaler.do
tb_transition.v     + run_transition.do
tb_osd_overlay.v    + run_osd_overlay.do
tb_tmds_encoder.v   + run_tmds_encoder.do
```

运行示例（在 `sim_work` 目录）：
```powershell
cd sim_work
vsim -c -do ../sim_tb/display/run_color_space.do
```
