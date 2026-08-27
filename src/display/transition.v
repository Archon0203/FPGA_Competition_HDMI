// ================================================================
// 模块   : transition
// 功能   : 图片转场。对 A/B 两路像素流做:
//           0 无转场(输出 A)   1 淡入淡出(线性交叉)
//           2 水平擦拭(B 自左向右覆盖 A)
//           t[7:0] 为进度 0..255(255=完全切到 B)。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 像素时钟与复位
//   - valid               : 像素有效
//   - mode[1:0]           : 0=直接A 1=淡入淡出 2=水平擦拭
//   - t[7:0]              : 转场进度(0..255)
//   - ax, ay[11:0]        : 输出像素坐标(擦拭用)
//   - a_r/a_g/a_b, b_r/b_g/b_b[7:0] : 两路像素(A=当前, B=下一张)
//   - out_r/out_g/out_b[7:0], out_valid : 输出
// 参数:
//   - DST_W               : 输出宽度(用于擦拭阈值), 默认 640
// 时钟域: clk 为像素时钟域(clk_pix)。组合逻辑输出。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T13 实现。
// ================================================================

module transition #(
    parameter integer DST_W = 640,
    parameter        DW     = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid,
    input  wire [1:0]  mode,
    input  wire [7:0]  t,
    input  wire [11:0] ax,
    input  wire [11:0] ay,
    input  wire [DW-1:0] a_r, a_g, a_b,
    input  wire [DW-1:0] b_r, b_g, b_b,
    output reg  [DW-1:0] out_r, out_g, out_b,
    output wire          out_valid
);

    assign out_valid = valid;

    // 单通道淡入淡出: out = (A*(255-t) + B*t) / 255  (端点精确)
    function [DW-1:0] blend;
        input [DW-1:0] a;
        input [DW-1:0] b;
        input [7:0]    tt;
        reg [17:0]      num;
        begin
            num   = (a * (8'd255 - tt)) + (b * tt);
            blend = num / 255;
        end
    endfunction

    // 水平擦拭阈值: B 从左侧覆盖, width 随 t 0..255 线性到满宽
    wire [19:0] thresh = (t * DST_W) / 255;
    wire        show_b_w = (ax < thresh[11:0]);    // 左侧显示 B/新图

    always @(*) begin
        if (!valid) begin
            out_r = {DW{1'b0}};
            out_g = {DW{1'b0}};
            out_b = {DW{1'b0}};
        end else begin
            case (mode)
                2'd0: begin out_r = a_r; out_g = a_g; out_b = a_b; end
                2'd1: begin
                    out_r = blend(a_r, b_r, t);
                    out_g = blend(a_g, b_g, t);
                    out_b = blend(a_b, b_b, t);
                end
                2'd2: begin
                    if (show_b_w) begin out_r = b_r; out_g = b_g; out_b = b_b; end
                    else          begin out_r = a_r; out_g = a_g; out_b = a_b; end
                end
                default: begin out_r = a_r; out_g = a_g; out_b = a_b; end
            endcase
        end
    end

endmodule
