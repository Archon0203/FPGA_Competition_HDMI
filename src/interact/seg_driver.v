// ================================================================
// 模块   : seg_driver
// 功能   : 8 位数码管动态扫描驱动 + 7 段译码。
//           每 SCAN_CLKS 拍切换一个位选, 依次点亮 digit0..digit7。
//           digits[31:0] = 8 个 4bit BCD: digits[3:0]=digit0 ... digits[31:28]=digit7
//           seg_data 高电平点亮(1=段 on), dp 也包含在内(bit7)。
//           输出按 ACTIVE_LOW 取反以适配共阴/共阳面板(板卡默认共阳低有效)。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 系统时钟与复位
//   - digits[31:0]        : 8 个 BCD 数码(每 4bit 一位, 高位为 digit7)
//   - dp[7:0]             : 小数点, 对应位为 1 则点亮该位 dp
//   - seg_sel[7:0]        : 位选(ACTIVE_LOW 时 0=点亮该位)
//   - seg_data[7:0]       : 段选(a..g,dp; ACTIVE_LOW 时 0=点亮该段)
// 参数:
//   - SCAN_CLKS           : 每个位选保持的时钟数, 默认 62500(约 800Hz 扫描)
//   - ACTIVE_LOW          : 1=低有效(共阳), 0=高有效(共阴)
// 时钟域: clk 为系统时钟域。模块自动分频产生扫描节拍。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T20 实现。
// ================================================================

module seg_driver #(
    parameter integer SCAN_CLKS = 62500,
    parameter        ACTIVE_LOW = 1'b1
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] digits,
    input  wire [7:0]  dp,
    output wire [7:0]  seg_sel,
    output wire [7:0]  seg_data
);

    localparam integer CW = $clog2(SCAN_CLKS);   // 扫描计数位宽
    localparam integer ND = 8;                    // 位数

    reg [CW-1:0] scan_cnt;
    reg [2:0]    digit_idx;   // 0..7

    // 扫描节拍: 每 SCAN_CLKS 拍切换位
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt  <= {CW{1'b0}};
            digit_idx <= 3'd0;
        end else if (scan_cnt == SCAN_CLKS[CW-1:0] - 1'b1) begin
            scan_cnt  <= {CW{1'b0}};
            digit_idx <= digit_idx + 1'b1;
        end else begin
            scan_cnt <= scan_cnt + 1'b1;
        end
    end

    // 当前位对应的 BCD 与 dp
    wire [3:0] cur_digit = digits[digit_idx*4 +: 4];

    // 7 段译码(高电平点亮: a=bit0, b=bit1, ..., g=bit6)
    function [6:0] seg7;
        input [3:0] n;
        begin
            case (n)
                4'h0: seg7 = 7'h3F;
                4'h1: seg7 = 7'h06;
                4'h2: seg7 = 7'h5B;
                4'h3: seg7 = 7'h4F;
                4'h4: seg7 = 7'h66;
                4'h5: seg7 = 7'h6D;
                4'h6: seg7 = 7'h7D;
                4'h7: seg7 = 7'h07;
                4'h8: seg7 = 7'h7F;
                4'h9: seg7 = 7'h6F;
                4'hA: seg7 = 7'h77;
                4'hB: seg7 = 7'h7C;
                4'hC: seg7 = 7'h39;
                4'hD: seg7 = 7'h5E;
                4'hE: seg7 = 7'h79;
                4'hF: seg7 = 7'h71;
                default: seg7 = 7'h00;
            endcase
        end
    endfunction

    // 段数据(含 dp)
    wire [7:0] seg_hi = {dp[digit_idx], seg7(cur_digit)};

    // 位选: 一轮 8 位, 低有效时 0=点亮
    wire [7:0] sel_pos = (8'b1 << digit_idx);

    assign seg_sel  = ACTIVE_LOW ? ~sel_pos  : sel_pos;
    assign seg_data = ACTIVE_LOW ? ~seg_hi   : seg_hi;

endmodule
