// ================================================================
// 模块   : dual_led
// 功能   : 4 组双色 LED(绿/红)状态指示。根据 mode[2:0] 输出绿/红电平,
//           支持常亮与慢/快闪烁及绿红交替。
//   mode:  0=全灭  1=绿常亮  2=红常亮  3=绿慢闪  4=红慢闪
//          5=绿红交替(慢)  6=黄(绿+红)常亮  7=红快闪(应急)
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 系统时钟与复位
//   - mode[2:0]           : 状态指示模式(见上)
//   - led_g[3:0]/led_r[3:0]: 绿/红输出, 1=点亮(可再按板卡极性取反)
// 参数:
//   - SLOW_CLKS           : 慢闪半周期时钟数, 默认 25e6(约 1Hz 闪烁)
//   - FAST_CLKS           : 快闪半周期时钟数, 默认 5e6(应付应急)
// 时钟域: clk 为系统时钟域。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T21 实现。
// ================================================================

module dual_led #(
    parameter integer SLOW_CLKS = 25000000,
    parameter integer FAST_CLKS = 5000000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [2:0] mode,
    output wire [3:0] led_g,
    output wire [3:0] led_r
);

    localparam integer SLOW_W = $clog2(SLOW_CLKS);
    localparam integer FAST_W = $clog2(FAST_CLKS);

    reg [SLOW_W-1:0] slow_cnt;
    reg [FAST_W-1:0] fast_cnt;
    reg              slow_phase;
    reg              fast_phase;

    // 慢闪节拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slow_cnt  <= {SLOW_W{1'b0}};
            slow_phase<= 1'b0;
        end else if (slow_cnt == SLOW_CLKS[SLOW_W-1:0] - 1'b1) begin
            slow_cnt  <= {SLOW_W{1'b0}};
            slow_phase<= ~slow_phase;
        end else begin
            slow_cnt <= slow_cnt + 1'b1;
        end
    end

    // 快闪节拍(应急)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fast_cnt  <= {FAST_W{1'b0}};
            fast_phase<= 1'b0;
        end else if (fast_cnt == FAST_CLKS[FAST_W-1:0] - 1'b1) begin
            fast_cnt  <= {FAST_W{1'b0}};
            fast_phase<= ~fast_phase;
        end else begin
            fast_cnt <= fast_cnt + 1'b1;
        end
    end

    // 根据 mode 解码单组绿/红电平
    reg g_led, r_led;
    always @(*) begin
        case (mode)
            3'd0: begin g_led = 1'b0; r_led = 1'b0; end
            3'd1: begin g_led = 1'b1; r_led = 1'b0; end
            3'd2: begin g_led = 1'b0; r_led = 1'b1; end
            3'd3: begin g_led = slow_phase; r_led = 1'b0; end
            3'd4: begin g_led = 1'b0; r_led = slow_phase; end
            3'd5: begin g_led = slow_phase; r_led = ~slow_phase; end
            3'd6: begin g_led = 1'b1; r_led = 1'b1; end
            3'd7: begin g_led = 1'b0; r_led = fast_phase; end
            default: begin g_led = 1'b0; r_led = 1'b0; end
        endcase
    end

    // 4 组一致(可根据需要扩展为逐组不同)
    assign led_g = {4{g_led}};
    assign led_r = {4{r_led}};

endmodule
