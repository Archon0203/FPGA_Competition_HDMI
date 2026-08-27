# src/display
显示处理流水线模块（✓=已完成并有 testbench）：
- `vga_timing.v` ✓：行场时序（HS/VS/DE + 像素坐标）
- `image_enhance.v` ✓：亮度(bias)/对比度(gain)逐像素增强
- `color_space.v` ✓：YCbCr→RGB（BT.601 定点矩阵）+ valid 握手
- `image_scaler.v` ✓：最近邻缩放坐标映射（任意源→目标分辨率）
- `transition.v` ✓：淡入淡出/水平擦拭转场（双图 A/B + alpha）
- `osd_overlay.v` ✓：8×16 字模字符叠加（点阵 ROM + 位置混合）
- `tmds_encoder.v`（后续）：TMDS 编码 + 串行化，用官方 lab_ex 参考
