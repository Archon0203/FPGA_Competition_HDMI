// ================================================================
// 模块   : beep
// 功能   : 蜂鸣器驱动。beep_en 为使能, mode 选择：
//           0=静音  1=连续音  2=断续音(门控 on/off)
//           输出方波音调(占空 50%), 频率由 TONE_HALF 决定。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 系统时钟与复位
//   - beep_en             : 使能(高)
//   - mode[1:0]           : 0=静音 1=连续 2=断续
//   - buzzer              : 蜂鸣器输出(ACTIVE_HIGH=1 时高为响)
// 参数:
//   - TONE_HALF           : 半个音调的时钟数, 默认 2500
//   - GATE_CLKS           : 门控半周期时钟数(断续用), 默认 250000
//   - ACTIVE_HIGH         : 输出有效电平
// 时钟域: clk 为系统时钟域。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T22 实现。
// ================================================================

module beep #(
    parameter integer TONE_HALF  = 2500,
    parameter integer GATE_CLKS  = 250000,
    parameter        ACTIVE_HIGH = 1'b1
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       beep_en,
    input  wire [1:0] mode,
    output wire       buzzer
);

    localparam integer TW = $clog2(TONE_HALF);
    localparam integer GW = $clog2(GATE_CLKS);

    reg [TW-1:0] tcnt;
    reg          tone;
    reg [GW-1:0] gcnt;
    reg          gate;

    // 音调方波(始终运行, 仅在有效时输出)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tcnt <= {TW{1'b0}};
            tone <= 1'b0;
        end else if (tcnt == TONE_HALF[TW-1:0] - 1'b1) begin
            tcnt <= {TW{1'b0}};
            tone <= ~tone;
        end else begin
            tcnt <= tcnt + 1'b1;
        end
    end

    // 门控节拍(断续模式)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gcnt <= {GW{1'b0}};
            gate <= 1'b1;             // 默认先"响"半周期
        end else if (gcnt == GATE_CLKS[GW-1:0] - 1'b1) begin
            gcnt <= {GW{1'b0}};
            gate <= ~gate;
        end else begin
            gcnt <= gcnt + 1'b1;
        end
    end

    // 解码: 是否发声 + 是否门控
    wire en_on   = beep_en && (mode != 2'd0);
    wire gated   = (mode == 2'd2) ? gate : 1'b1;   // 模式2 才门控
    wire beep_hi = en_on && gated && tone;

    assign buzzer = ACTIVE_HIGH ? beep_hi : ~beep_hi;

endmodule
