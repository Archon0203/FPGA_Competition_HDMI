// ================================================================
// 模块   : bmp_parser
// 功能   : 解析 BMP(BITMAPINFOHEADER, 24 位非压缩)文件头。
//           逐字节消费输入流, 提取:
//             magic 'BM', width, height, bpp, data_offset(像素起始偏移)。
//           当字节计数到达 data_offset 时置 done, 此后像素数据开始。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 系统/读写时钟
//   - start               : 新文件开始脉冲(复位 byte_idx/字段)
//   - din[7:0] / din_valid: 输入字节流
//   - done                : 文件头解析完成(高, 持续到复位或下一文件)
//   - bmp_ok              : 魔数 'BM' 校验通过
//   - width[15:0]/height[15:0] : 图像宽高(原始, 高度可负表示倒序)
//   - bpp[5:0]            : 位深(如 24)
//   - data_offset[23:0]   : 像素数据在文件中的起始字节偏移
// 说明   : 小端解析; 仅支持 BITMAPINFOHEADER 风格, 供 SD 读取链路使用。
// 时钟域: clk 为 SD/读写时钟域(clk_sdo 或 clk_sys)。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T6 实现。
// ================================================================

module bmp_parser #(
    parameter integer W = 16,       // width 位宽
    parameter integer H = 16        // height 位宽
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [7:0]  din,
    input  wire        din_valid,
    output reg         done,
    output reg         bmp_ok,
    output reg  [W-1:0] width,
    output reg  [H-1:0] height,
    output reg  [5:0]  bpp,
    output reg  [23:0] data_offset
);

    reg [15:0] byte_idx;           // 当前字节序号(16 位, 容纳大偏移头)
    reg [7:0]  magic0, magic1;
    reg [7:0]  d10, d11, d12, d13;  // data_offset 小端字节
    reg [7:0]  w18, w19, w20, w21;  // width 小端字节
    reg [7:0]  h22, h23, h24, h25;  // height 小端字节
    reg [7:0]  b28, b29;            // bpp 小端字节
    reg [7:0]  d14, d15, d16, d17;  // DIB header size
    reg [7:0]  p26, p27;            // planes
    reg [7:0]  c30, c31, c32, c33;  // compression

    // 字节计数
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) byte_idx <= 16'd0;
        else if (start) byte_idx <= 16'd0;
        else if (din_valid) byte_idx <= byte_idx + 1'b1;
    end

    // 逐字节提取(在计数尚未递增的那一拍, 用当前 byte_idx 匹配)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            magic0 <= 8'd0; magic1 <= 8'd0;
            d10<=8'd0; d11<=8'd0; d12<=8'd0; d13<=8'd0;
            w18<=8'd0; w19<=8'd0; w20<=8'd0; w21<=8'd0;
            h22<=8'd0; h23<=8'd0; h24<=8'd0; h25<=8'd0;
            b28<=8'd0; b29<=8'd0;
            d14<=8'd0; d15<=8'd0; d16<=8'd0; d17<=8'd0;
            p26<=8'd0; p27<=8'd0; c30<=8'd0; c31<=8'd0; c32<=8'd0; c33<=8'd0;
        end else if (start) begin
            magic0 <= 8'd0; magic1 <= 8'd0;
            d10<=8'd0; d11<=8'd0; d12<=8'd0; d13<=8'd0;
            w18<=8'd0; w19<=8'd0; w20<=8'd0; w21<=8'd0;
            h22<=8'd0; h23<=8'd0; h24<=8'd0; h25<=8'd0;
            b28<=8'd0; b29<=8'd0;
            d14<=8'd0; d15<=8'd0; d16<=8'd0; d17<=8'd0;
            p26<=8'd0; p27<=8'd0; c30<=8'd0; c31<=8'd0; c32<=8'd0; c33<=8'd0;
        end else if (din_valid) begin
            case (byte_idx)
                12'd0: magic0 <= din;
                12'd1: magic1 <= din;
                12'd10: d10 <= din;
                12'd11: d11 <= din;
                12'd12: d12 <= din;
                12'd13: d13 <= din;
                12'd14: d14 <= din;
                12'd15: d15 <= din;
                12'd16: d16 <= din;
                12'd17: d17 <= din;
                12'd18: w18 <= din;
                12'd19: w19 <= din;
                12'd20: w20 <= din;
                12'd21: w21 <= din;
                12'd22: h22 <= din;
                12'd23: h23 <= din;
                12'd24: h24 <= din;
                12'd25: h25 <= din;
                12'd26: p26 <= din;
                12'd27: p27 <= din;
                12'd28: b28 <= din;
                12'd29: b29 <= din;
                12'd30: c30 <= din;
                12'd31: c31 <= din;
                12'd32: c32 <= din;
                12'd33: c33 <= din;
                default: ;
            endcase
        end
    end

    // 组装输出(组合)
    wire [23:0] off = {d13, d12, d11, d10};
    wire [15:0] wid = {w21, w20, w19, w18};
    wire [15:0] hgt = {h25, h24, h23, h22};
    wire [15:0] bpp16 = {b29, b28};
    wire [31:0] dib_size = {d17,d16,d15,d14};
    wire [15:0] planes   = {p27,p26};
    wire [31:0] compression = {c33,c32,c31,c30};

    always @(*) begin
        data_offset = off;
        width       = wid;
        height      = hgt;
        bpp         = bpp16[5:0];
    end

    // done: 头最后一个字节(dat_offset-1)消费完成时脉冲一拍；
    //       下一拍 din_valid 对应的字节就是首个 pixel byte。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                               done <= 1'b0;
        else if (start)                           done <= 1'b0;
        else if (din_valid && byte_idx == data_offset - 1'b1) done <= 1'b1;
        else                                      done <= 1'b0;
    end

    // 魔数校验
    always @(*) bmp_ok = (magic0 == 8'h42) && (magic1 == 8'h4D) &&
                         (dib_size == 32'd40) && (planes == 16'd1) &&
                         (bpp16 == 16'd24) && (compression == 32'd0);

endmodule
