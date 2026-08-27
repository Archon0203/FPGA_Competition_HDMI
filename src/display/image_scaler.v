// ================================================================
// 模块   : image_scaler
// 功能   : 最近邻(Nearest-Neighbor)缩放坐标映射。
//           对每个输出像素(px,py), 计算需取样的源像素坐标(sx,sy):
//           sx = floor(px * SRC_W / DST_W),  sy = floor(py * SRC_H / DST_H)
//           并 clamp 到 [0, SRC_W-1] / [0, SRC_H-1]。
//           该模块只输出"取哪个源像素", 实际像素数据由上游帧缓冲/行缓存按地址取。
//           支持任意输入分辨率 -> 输出分辨率(不要求整数倍)。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 像素时钟与复位
//   - valid               : 输出像素有效(可由 vga_timing.de 驱动)
//   - px, py[11:0]        : 输出像素坐标(0..DST_W-1 / 0..DST_H-1)
//   - src_valid           : 源坐标有效(延迟一拍)
//   - sx, sy[11:0]        : 源像素坐标
// 参数:
//   - SRC_W / SRC_H       : 源分辨率, 默认 320x240
//   - DST_W / DST_H       : 输出分辨率, 默认 640x480
// 时钟域: clk 为像素时钟域(clk_pix)。含 1 拍流水延迟。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T11 实现。
//   2026-08-27 v1.1 坐标乘积显式扩展到 32 位，避免大分辨率截断。
// ================================================================

module image_scaler #(
    parameter integer SRC_W = 320,
    parameter integer SRC_H = 240,
    parameter integer DST_W = 640,
    parameter integer DST_H = 480
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid,
    input  wire [11:0] px,
    input  wire [11:0] py,
    output reg  [11:0] sx,
    output reg  [11:0] sy,
    output reg         src_valid
);

    // 最近邻源坐标(组合)。将坐标零扩展到 32 位，保证大分辨率也不会截断。
    wire [31:0] sx_prod = {20'b0, px} * SRC_W;
    wire [31:0] sy_prod = {20'b0, py} * SRC_H;
    wire [31:0] sx_raw  = sx_prod / DST_W;
    wire [31:0] sy_raw  = sy_prod / DST_H;

    // clamp 到源范围
    wire [11:0] sx_clamp = (sx_raw > SRC_W-1) ? (SRC_W-1) : sx_raw;
    wire [11:0] sy_clamp = (sy_raw > SRC_H-1) ? (SRC_H-1) : sy_raw;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sx        <= 12'd0;
            sy        <= 12'd0;
            src_valid <= 1'b0;
        end else begin
            sx        <= sx_clamp;
            sy        <= sy_clamp;
            src_valid <= valid;
        end
    end

endmodule
