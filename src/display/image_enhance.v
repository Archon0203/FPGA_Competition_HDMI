// ================================================================
// 模块   : image_enhance
// 功能   : 逐像素亮度(bias)/对比度(gain)调节, 组合逻辑输出。
//           输出 = clamp( (pixel-128)*gain/64 + 128 + bias )
//           gain: 8bit 无符号, 实际系数 = gain/64 (64=>1.0, 128=>2.0)
//           bias: 8bit 有符号亮度偏移
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 说明   : 纯 RTL, 无厂商 IP, 可用 tb_image_enhance 仿真。
//           接口与 vga_timing 的 de/pixel 流兼容(valid 手握手)。
// ================================================================

module image_enhance #(
    parameter DW = 8
)(
    input  wire        pixel_valid,          // 数据有效(可由 vga_timing.de 驱动)
    input  wire [DW-1:0] r_in,
    input  wire [DW-1:0] g_in,
    input  wire [DW-1:0] b_in,
    input  wire [7:0]    gain,               // 对比度, gain/64
    input  wire signed [7:0] bias,           // 亮度偏移
    output reg  [DW-1:0] r_out,
    output reg  [DW-1:0] g_out,
    output reg  [DW-1:0] b_out,
    output wire          out_valid
);

    assign out_valid = pixel_valid;

    // 单通道增强: clamp( (c-128)*ga/64 + 128 + bi )
    function [7:0] adj;
        input [7:0]      c;
        input [7:0]      ga;
        input signed [7:0] bi;
        reg signed [31:0] m;
        reg signed [31:0] s;
        begin
            m = $signed({24'b0, c}) - 32'sd128;      // -128..127
            m = m * $signed({24'b0, ga});            // * gain (0..255)
            s = m >>> 6;                              // /64
            s = s + 32'sd128;                         // + 128
            s = s + $signed(bi);                      // + brightness
            if (s < 0)       s = 32'd0;
            else if (s > 255) s = 32'd255;
            adj = s[7:0];
        end
    endfunction

    always @(*) begin
        if (pixel_valid) begin
            r_out = adj(r_in, gain, bias);
            g_out = adj(g_in, gain, bias);
            b_out = adj(b_in, gain, bias);
        end else begin
            r_out = 8'd0;
            g_out = 8'd0;
            b_out = 8'd0;
        end
    end

endmodule

