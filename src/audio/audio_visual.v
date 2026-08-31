// ================================================================
// 模块   : audio_visual
// 功能   : 音频可视化(低资源振幅包络柱状图, 不做完整 FFT)。
//           对输入 PCM 采样做"攻击快、释放慢"的峰值包络(env 0..255),
//           并在指定 x 区域内绘制一根自下而上的竖条(柱高 = env)。
//           供显示流水线以 vis_on 叠加到画面(overlay 用)。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-28
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效)   : 音频/像素时钟(通常为 clk_pix)
//   - sample_valid / sample : PCM 采样(有符号)入
//   - disp_valid / px / py   : 显示像素流(可由 vga_timing.de 驱动)
//   - level[ENV_W-1:0]      : 当前包络(默认取高字节, 16bit 时约为 0..127), 供状态/调试
//   - vis_on                : 该像素落在可视化柱内(高有效)
// 参数:
//   - DW                    : 采样位宽(默认 16)
//   - ENV_W                 : 包络位宽(默认 8, 0..255)
//   - BAR_X0 / BAR_W        : 柱状区起始 x 与宽度
//   - BAR_H                 : 柱状区最大高度(行数)
//   - DECAY                 : 释放步进(每采样下降量)
// 说明   : 低资源实现(一个包络寄存器 + 比较); 频谱类扩展可后续以多带 DFT 替换。
// 时钟域: clk 为像素时钟域(clk_pix); 采样按 sample_valid 采样。
// 修改历史:
//   2026-08-28 v1.0 初版, 按 docs/11 §1.5 A 组"音频可视化"实现。
// ================================================================

module audio_visual #(
    parameter integer DW     = 16,
    parameter integer ENV_W  = 8,
    parameter integer BAR_X0 = 560,
    parameter integer BAR_W  = 32,
    parameter integer BAR_H  = 256,
    parameter integer DECAY  = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_valid,
    input  wire signed [DW-1:0] sample,
    input  wire        disp_valid,
    input  wire [11:0] px,
    input  wire [11:0] py,
    output wire [ENV_W-1:0] level,
    output wire        vis_on
);

    localparam [11:0] BAR_X0_ = BAR_X0;
    localparam [11:0] BAR_W_  = BAR_W;
    localparam [11:0] BAR_H_  = BAR_H;

    // 采样幅值(先符号扩展到 DW+1 位，避免最小负数 -2^(DW-1) 取负溢出)
    wire signed [DW:0] s_ext = $signed(sample);
    wire signed [DW:0] s_abs = (sample < 0) ? -s_ext : s_ext;
    wire [ENV_W-1:0] amp = s_abs[DW-1 -: ENV_W];

    reg [ENV_W-1:0] env;

    // 攻击快、释放慢
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            env <= {ENV_W{1'b0}};
        end else if (sample_valid) begin
            if (amp >= env)                    env <= amp;          // 攻击
            else if (env >= DECAY[ENV_W-1:0])  env <= env - DECAY[ENV_W-1:0]; // 释放
            else                               env <= {ENV_W{1'b0}};
        end
    end

    assign level = env;

    // 柱高 = env 放大到接近 BAR_H(默认 16bit 输入时 x2), 再按 BAR_H clamp
    wire [ENV_W:0] env_x2 = {env, 1'b0};
    wire [ENV_W:0] bar_h  = (env_x2 > BAR_H_) ? BAR_H_[ENV_W:0] : env_x2;
    wire [11:0] bar_top  = BAR_H_ - bar_h;     // 柱顶行号(0 起)
    wire [11:0] bar_right = BAR_X0_ + BAR_W_;
    wire in_bar_x = (px >= BAR_X0_) && (px < bar_right);
    wire in_bar_y = (py >= bar_top) && (py < BAR_H_);

    assign vis_on = disp_valid && (bar_h > 0) && in_bar_x && in_bar_y;

endmodule
