# ================================================================
# mini-top 显示链集成仿真（在 sim_work 目录运行）：
#   cd sim_work
#   vsim -c -do ../sim_tb/top/run_mini_top.do
# ================================================================

vlib work
vlog ../src/display/vga_timing.v ../src/display/color_space.v \
     ../src/display/yuv420_upsample.v \
     ../src/display/image_enhance.v ../src/display/transition.v \
     ../src/display/osd_overlay.v ../sim_tb/top/tb_mini_top.v
vsim tb_mini_top
run -all
quit -f
