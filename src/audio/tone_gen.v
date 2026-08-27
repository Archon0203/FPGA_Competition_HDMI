// ================================================================
// 模块   : tone_gen
// 功能   : 数字音调发生器(DDS 相位累加器)。
//           每个 samples_valid 拍把 freq 加进相位; 由相位产生波表:
//           0=方波  1=三角波。输出有符号 PCM(定点, 全幅)。
//           频率 = freq * fsample / 2^N, 其中 fsample 为采样率。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 时钟与复位
//   - samples_valid       : 采样节拍(每个有效采样推进一次相位)
//   - freq[N-1:0]         : 相位增量(决定音高)
//   - wave[1:0]           : 0=方波 1=三角波
//   - pcm[DW-1:0]         : 有符号 PCM 输出
// 参数:
//   - N                   : 相位累加器位宽, 默认 16
//   - DW                  : PCM 位宽, 默认 16
// 时钟域: clk 为音频时钟域(clk_aud)。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T16 实现。
// ================================================================

module tone_gen #(
    parameter integer N  = 16,
    parameter integer DW = 16
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          samples_valid,
    input  wire [N-1:0]  freq,
    input  wire [1:0]    wave,
    output reg  signed [DW-1:0] pcm
);

    // 全幅幅度(对称)
    localparam signed [DW-1:0] AMP = (DW > 1) ? ({1'b0, {DW-1{1'b1}}}) : 1; // 2^(DW-1)-1

    reg [N-1:0] phase;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          phase <= {N{1'b0}};
        else if (samples_valid) phase <= phase + freq;
    end

    // 方波(相位 MSB 决定符号)
    wire sq_hi = phase[N-1];

    // 三角波: 用 N-1 位取折返, 产生线性三角(中心化)
    wire [N-2:0] tri_half = phase[N-2:0];
    wire [N-2:0] tri_abs  = sq_hi ? (~tri_half) : tri_half;
    // 映射到有符号: 用 {1'b0,tri_abs} 清零扩展后减 2^(N-2), 得到 -2^(N-2)..+2^(N-2)-1
    wire signed [DW-1:0] tri_signed = $signed({1'b0, tri_abs} - (1 <<< (N-2)));

    always @(*) begin
        case (wave)
            2'd0: pcm = sq_hi ? AMP : -AMP;
            2'd1: pcm = tri_signed;
            default: pcm = 16'sd0;
        endcase
    end

endmodule
