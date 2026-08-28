// ================================================================
// 模块   : tmds_encoder
// 功能   : TMDS 8b/10b 纯逻辑编码器（DVI/HDMI 数据通道）。
//           仅实现 8bit 像素 -> 9bit q_m -> 10bit q_out 与 DC 平衡，
//           以及消隐期控制码编码。串行化/OSERDES/差分输出不在此模块。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-28
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 像素时钟与异步复位
//   - din[7:0]            : 单通道 8bit 数据(红/绿/蓝之一)
//   - de                  : 数据有效(1=像素数据, 0=控制周期)
//   - c0 / c1             : 控制输入(消隐期编码为固定控制码)
//   - dout[9:0]           : TMDS 10bit 编码输出
// 时钟域: clk 为像素时钟域(clk_pix)。
// 说明   : 输出相对 din 延迟一拍；消隐期 disparity 计数器复位为 0。
// 修改历史:
//   2026-08-28 v1.0 初版, 按 docs/11 §1.5 A 组实现。
// ================================================================

module tmds_encoder #(
    parameter DW = 8
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          de,
    input  wire          c0,
    input  wire          c1,
    input  wire [DW-1:0] din,
    output reg  [9:0]    dout
);

    localparam [9:0] CTRL_00 = 10'b1101010100;
    localparam [9:0] CTRL_01 = 10'b0010101011;
    localparam [9:0] CTRL_10 = 10'b0101010100;
    localparam [9:0] CTRL_11 = 10'b1010101011;

    reg             de_r, c0_r, c1_r;
    reg [DW-1:0]    din_r;
    reg signed [4:0] cnt;

    function [3:0] count8;
        input [7:0] v;
        integer i;
        begin
            count8 = 4'd0;
            for (i = 0; i < 8; i = i + 1)
                count8 = count8 + v[i];
        end
    endfunction

    // 8bit -> 9bit 的第一阶段
    wire [3:0] n1d      = count8(din_r);
    wire       decision1 = (n1d > 4'd4) || ((n1d == 4'd4) && (din_r[0] == 1'b0));

    reg [8:0] q_m;
    integer   qi;
    always @(*) begin
        q_m[0] = din_r[0];
        for (qi = 1; qi < 8; qi = qi + 1) begin
            q_m[qi] = decision1 ? (q_m[qi-1] ~^ din_r[qi])
                                : (q_m[qi-1]  ^ din_r[qi]);
        end
        q_m[8] = decision1 ? 1'b0 : 1'b1;
    end

    wire [3:0] n1q_m = count8(q_m[7:0]);
    wire [3:0] n0q_m = 4'd8 - n1q_m;
    wire       decision2 = (cnt == 5'sd0) || (n1q_m == n0q_m);
    wire       decision3 = ((cnt > 5'sd0) && (n1q_m > n0q_m)) ||
                           ((cnt < 5'sd0) && (n0q_m > n1q_m));

    wire signed [5:0] n1s = $signed({{2{1'b0}}, n1q_m});
    wire signed [5:0] n0s = $signed({{2{1'b0}}, n0q_m});
    wire signed [5:0] inc2 = q_m[8] ? 6'sd2 : 6'sd0;
    wire signed [5:0] dec2 = q_m[8] ? 6'sd0 : 6'sd2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            din_r <= {DW{1'b0}};
            de_r  <= 1'b0;
            c0_r  <= 1'b0;
            c1_r  <= 1'b0;
            cnt   <= 5'sd0;
            dout  <= 10'd0;
        end else begin
            din_r <= din;
            de_r  <= de;
            c0_r  <= c0;
            c1_r  <= c1;

            if (de_r) begin
                if (decision2) begin
                    dout[9]   <= ~q_m[8];
                    dout[8]   <= q_m[8];
                    dout[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                    cnt       <= q_m[8] ? (cnt + n1s - n0s)
                                        : (cnt + n0s - n1s);
                end else if (decision3) begin
                    dout[9]   <= 1'b1;
                    dout[8]   <= q_m[8];
                    dout[7:0] <= ~q_m[7:0];
                    cnt       <= cnt + inc2 + n0s - n1s;
                end else begin
                    dout[9]   <= 1'b0;
                    dout[8]   <= q_m[8];
                    dout[7:0] <= q_m[7:0];
                    cnt       <= cnt - dec2 + n1s - n0s;
                end
            end else begin
                case ({c1_r, c0_r})
                    2'b00:   dout <= CTRL_00;
                    2'b01:   dout <= CTRL_01;
                    2'b10:   dout <= CTRL_10;
                    default: dout <= CTRL_11;
                endcase
                cnt <= 5'sd0;
            end
        end
    end

endmodule
