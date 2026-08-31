// ================================================================
// 模块   : color_space
// 功能   : YCbCr(ITU-R BT.601, 有限范围) -> RGB888 定点矩阵转换。
//           Y 先按 limited-range 展开: Y' = 1.164*(Y-16)。
//           R = 1.164*(Y-16) + 1.596*(Cr-128)
//           G = 1.164*(Y-16) - 0.392*(Cb-128) - 0.813*(Cr-128)
//           B = 1.164*(Y-16) + 2.017*(Cb-128)
//           定点: 系数放大 256 倍(Q8), 最后加 0.5 舍入, 输出做 0..255 clamp。
//           本模块按逐像素 YUV444 处理(每像素带一份 Cb/Cr)。
//           YUV420 的色度上采样(最近邻/双线性)属于前置阶段, 另行实现。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效)  : 像素时钟与复位
//   - pixel_valid          : 数据有效(可由 vga_timing.de 或上游握手驱动)
//   - y, cb, cr[7:0]       : 输入像素 YCbCr
//   - out_valid            : 输出有效(= pixel_valid, 组合传递)
//   - r, g, b[7:0]         : 输出 RGB888(组合逻辑)
// 时钟域: clk 为像素时钟域(clk_pix)。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T10(示例卡2)实现。
//   2026-08-27 v1.1 修复 BT.601 定点乘法被表达式位宽截断的问题。
//   2026-08-30 v1.2 修正为真正的 limited-range BT.601，并增加四舍五入。
// ================================================================

module color_space #(
    parameter DW = 8
)(
    input  wire [DW-1:0] y,
    input  wire [DW-1:0] cb,
    input  wire [DW-1:0] cr,
    input  wire          pixel_valid,
    output reg  [DW-1:0] r,
    output reg  [DW-1:0] g,
    output reg  [DW-1:0] b,
    output wire          out_valid
);

    // Q8 系数。显式放到 32 位，避免 Verilog 乘法按“操作数最大位宽”截断。
    localparam signed [31:0] K_Y    = 32'sd298;   // 1.164 * 256
    localparam signed [31:0] K_R_CR = 32'sd409;   // 1.596 * 256
    localparam signed [31:0] K_G_CB = -32'sd100;  // -0.392 * 256
    localparam signed [31:0] K_G_CR = -32'sd208;  // -0.813 * 256
    localparam signed [31:0] K_B_CB = 32'sd516;   // 2.017 * 256

    assign out_valid = pixel_valid;

    // 色度去中心(0..255 -> -128..127)，先零扩展到 32 位再做有符号运算。
    wire signed [31:0] cbc = $signed({24'b0, cb}) - 32'sd128;
    wire signed [31:0] crc = $signed({24'b0, cr}) - 32'sd128;
    wire signed [31:0] yd  = $signed({24'b0, y})  - 32'sd16;

    // 定点矩阵：先乘加得到 Q8 结果，再加 0.5*256 做四舍五入。
    wire signed [31:0] y_base = $signed(yd) * K_Y;
    wire signed [31:0] r_sum = y_base + ($signed(crc) * K_R_CR) + 32'sd128;
    wire signed [31:0] g_sum = y_base + ($signed(cbc) * K_G_CB) + ($signed(crc) * K_G_CR) + 32'sd128;
    wire signed [31:0] b_sum = y_base + ($signed(cbc) * K_B_CB) + 32'sd128;

    function [7:0] clip;
        input signed [31:0] v;
        begin
            if (v < 32'sd0)      clip = 8'd0;
            else if (v > 32'sd255) clip = 8'd255;
            else                 clip = v[7:0];
        end
    endfunction

    always @(*) begin
        if (pixel_valid) begin
            r = clip(r_sum >>> 8);
            g = clip(g_sum >>> 8);
            b = clip(b_sum >>> 8);
        end else begin
            r = {DW{1'b0}};
            g = {DW{1'b0}};
            b = {DW{1'b0}};
        end
    end

endmodule
