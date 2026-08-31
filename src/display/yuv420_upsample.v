// ================================================================
// 模块   : yuv420_upsample
// 功能   : YUV420 -> YUV444 最近邻色度上采样。
//           内部用**色度行缓冲**(长度 = 宽/2): 偶数亮行在每块左上像素写入
//           当前块 cb/cr, 奇数亮行沿用上一偶数行(同块行)缓冲, 实现水平+垂直复制。
//           输出带 1 拍寄存器延迟(与像素流对齐)。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-28
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 像素时钟与复位
//   - pix_valid / px / py : 像素有效与坐标(px 用于行缓冲读写索引)
//   - c_valid             : 色度有效(每 2x2 块左上像素一拍)
//   - y_in / cb_in / cr_in: 输入亮度与块色度(8bit)
//   - out_valid / y_out / cb_out / cr_out : 输出 YUV444
//   - out_px / out_py                   : 与输出数据同拍延迟的像素坐标
// 说明   : 上游色度时序须为"块左上像素处给出该块 cb/cr"; 用作 color_space 前置。
// 时钟域: clk 为像素时钟域(clk_pix)。含 1 拍流水延迟。
// 修改历史:
//   2026-08-28 v1.0 初版, 按 docs/11 §1.5 A 组实现。
// ================================================================

module yuv420_upsample #(
    parameter integer HW = 320,     // 半宽(色度列数 = W/2)
    parameter        DW = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pix_valid,
    input  wire [11:0] px,
    input  wire [11:0] py,
    input  wire        c_valid,
    input  wire [DW-1:0] y_in,
    input  wire [DW-1:0] cb_in,
    input  wire [DW-1:0] cr_in,
    output reg  [DW-1:0] y_out,
    output reg  [DW-1:0] cb_out,
    output reg  [DW-1:0] cr_out,
    output reg            out_valid,
    output reg  [11:0]    out_px,
    output reg  [11:0]    out_py
);

    reg [DW-1:0] cb_row [0:HW-1];
    reg [DW-1:0] cr_row [0:HW-1];
    wire [10:0] cidx = px >> 1;      // 色度列索引 = px/2 (11 位足够覆盖 640 宽的半宽 320)

    // 色度行缓冲: 偶数亮行(即色度块行)在块首像素写入。
    // 行 RAM 不复位，避免把块 RAM 综合成带异步清零的大量 FF。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 保留复位后首块通过 c_valid 写入的行 RAM 行为。
        end else if (c_valid) begin
            cb_row[cidx] <= cb_in;
            cr_row[cidx] <= cr_in;
        end
    end

    // 输出寄存器(1 拍延迟, 使像素与色度对齐)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_px    <= 12'd0;
            out_py    <= 12'd0;
            y_out <= {DW{1'b0}}; cb_out <= {DW{1'b0}}; cr_out <= {DW{1'b0}};
        end else begin
            out_valid <= pix_valid;
            out_px    <= px;
            out_py    <= py;
            y_out     <= y_in;
            cb_out    <= c_valid ? cb_in : cb_row[cidx];   // 块首用新色度, 否则行缓冲
            cr_out    <= c_valid ? cr_in : cr_row[cidx];
        end
    end

endmodule
