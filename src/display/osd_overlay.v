// ================================================================
// 模块   : osd_overlay
// 功能   : 字符叠加。在视频流的指定矩形(8x16 字符单元)内, 按字模 ROM
//           决定是否用前景色替代背景像素; 其余位置透传视频。
//           char_code 索引字模(当前内置 3 个测试字模, 真实字模可由
//           tools/gen_font.py 生成并替换本 ROM 的 initial 数据)。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 像素时钟与复位
//   - valid / x / y        : 像素流与坐标
//   - r_in/g_in/b_in       : 背景视频像素
//   - osd_en               : OSD 使能
//   - osd_x/osd_y          : 字符单元左上角坐标
//   - char_code[3:0]       : 字符索引(0..15)
//   - fg_r/fg_g/fg_b       : 前景色(文字颜色)
//   - out_r/out_g/out_b / out_valid : 输出
// 参数:
//   - FW=8, FH=16          : 字符字模宽高
// 时钟域: clk 为像素时钟域(clk_pix)。组合逻辑输出。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T14 实现。
// ================================================================

module osd_overlay #(
    parameter integer FW = 8,
    parameter integer FH = 16,
    parameter        DW = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire [DW-1:0] r_in, g_in, b_in,
    input  wire          osd_en,
    input  wire [11:0] osd_x,
    input  wire [11:0] osd_y,
    input  wire [3:0]  char_code,
    input  wire [DW-1:0] fg_r, fg_g, fg_b,
    output reg  [DW-1:0] out_r, out_g, out_b,
    output wire          out_valid
);

    localparam integer ROW_W = (FH > 1) ? $clog2(FH) : 1;
    localparam integer COL_W = (FW > 1) ? $clog2(FW) : 1;

    // 字模 ROM: 16 字形 x 16 行 x 8 列  (char_code*16 + row -> 8 bits)
    reg [FW-1:0] font_rom [0:15] [0:FH-1];
    integer fi, fj;
    initial begin
        // 清空所有字形
        for (fi = 0; fi < 16; fi = fi + 1)
            for (fj = 0; fj < FH; fj = fj + 1)
                font_rom[fi][fj] = {FW{1'b0}};
        // 字模 1: 实心块(测试用, 用于验证位置/混合)
        for (fj = 0; fj < FH; fj = fj + 1) font_rom[1][fj] = {FW{1'b1}};
        // 字模 2: 上半实心(验证 行范围)
        for (fj = 0; fj < FH/2; fj = fj + 1) font_rom[2][fj] = {FW{1'b1}};
        // 其余(0,3..15) 全 0(透明)
    end

    assign out_valid = valid;

    // 计算单元格内位置
    wire [15:0] rx = x - osd_x;
    wire [15:0] ry = y - osd_y;
    wire        in_cell = osd_en && (rx < FW) && (ry < FH);

    // 取字模点
    wire [FW-1:0] row_bits = font_rom[char_code][ry[ROW_W-1:0]];
    wire          dot      = in_cell ? row_bits[rx[COL_W-1:0]] : 1'b0;

    always @(*) begin
        if (!valid) begin
            out_r = {DW{1'b0}}; out_g = {DW{1'b0}}; out_b = {DW{1'b0}};
        end else if (dot) begin
            out_r = fg_r; out_g = fg_g; out_b = fg_b;
        end else begin
            out_r = r_in; out_g = g_in; out_b = b_in;
        end
    end

endmodule
