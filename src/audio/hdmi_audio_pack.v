// ================================================================
// 模块   : hdmi_audio_pack
// 功能   : HDMI L-PCM 音频的 IEC60958 子帧打包（纯逻辑）。
//           将一个 24bit 线性 PCM 采样打包为 28bit 子帧数据：
//           bit[23:0] = audio sample(LSB 在前, 即 slot4..slot27)
//           bit[24]   = V(validity)
//           bit[25]   = U(user data)
//           bit[26]   = C(channel status)
//           bit[27]   = P(偶校验, 覆盖 bit[27:0] 前的 27 bit)
//           本模块只做“采样打包+校验”，Data Island 到 TMDS 通道的注入
//           属 B 组/官方参考，不在本模块实现。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-28
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 音频时钟与异步复位
//   - sample_valid        : 采样有效
//   - sample[23:0]        : 有符号 L-PCM 采样
//   - v / u / c           : IEC60958 V/U/C 位
//   - subframe_valid      : 输出有效(延迟一拍)
//   - subframe[27:0]      : IEC60958 slot4..slot31
// 时钟域: clk 为音频时钟域(clk_aud)。
// 修改历史:
//   2026-08-28 v1.0 初版, 按 docs/11 §1.5 A 组实现。
// ================================================================

module hdmi_audio_pack #(
    parameter AW = 24
)(
    input  wire           clk,
    input  wire           rst_n,
    input  wire           sample_valid,
    input  wire signed [AW-1:0] sample,
    input  wire           v,
    input  wire           u,
    input  wire           c,
    output reg            subframe_valid,
    output reg  [AW+3:0]  subframe
);

    // IEC60958: 偶校验覆盖 sample(24bit)+V+U+C 共 27bit。
    wire parity = ^sample ^ v ^ u ^ c;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            subframe_valid <= 1'b0;
            subframe       <= {(AW+4){1'b0}};
        end else begin
            subframe_valid <= sample_valid;
            subframe       <= {parity, c, u, v, sample};
        end
    end

endmodule
