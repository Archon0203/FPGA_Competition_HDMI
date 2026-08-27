// ================================================================
// 模块   : app_scenario
// 功能   : 应用场景状态机("校园/园区信息发布与应急广播终端"):
//           - 常态: 图片自动轮播(每 SLIDE_CLKS 拍切换), 支持上/下张, 播放/暂停
//           - 应急: emergency=1 时进入应急页, 输出提示音使能
//           index 为当前图片/片段索引(0..IMG_COUNT-1), 循环。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效)  : 系统时钟与复位
//   - play_en              : 1=播放(自动轮播) 0=暂停
//   - emergency            : 1=应急模式
//   - cmd_next/cmd_prev    : 上/下一张命令(单拍, 来自 menu_fsm)
//   - index[7:0]           : 当前内容索引
//   - slide_tick           : 自动切换脉冲(供外部读图/切图)
//   - beep_alert           : 应急提示音使能(电平, 应急期间=1)
//   - mode[1:0]            : 0=常态 1=应急
// 参数:
//   - IMG_COUNT            : 内容数量(默认 4)
//   - SLIDE_CLKS           : 自动轮播间隔时钟数(默认 100)
// 时钟域: clk 为系统时钟域(clk_sys)。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T23 实现。
// ================================================================

module app_scenario #(
    parameter integer IMG_COUNT  = 4,
    parameter integer SLIDE_CLKS = 100
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        play_en,
    input  wire        emergency,
    input  wire        cmd_next,
    input  wire        cmd_prev,
    output reg  [7:0]  index,
    output reg         slide_tick,
    output reg         beep_alert,
    output reg  [1:0]  mode
);

    localparam integer TW = $clog2(SLIDE_CLKS);
    reg [TW-1:0] timer;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            index      <= 8'd0;
            timer      <= {TW{1'b0}};
            slide_tick <= 1'b0;
            beep_alert <= 1'b0;
            mode       <= 2'd0;
        end else begin
            slide_tick <= 1'b0;
            mode       <= emergency ? 2'd1 : 2'd0;
            beep_alert <= emergency;

            if (cmd_next) begin
                index <= (index >= IMG_COUNT-1) ? 8'd0 : index + 1'b1;
                timer <= {TW{1'b0}};
            end else if (cmd_prev) begin
                index <= (index == 8'd0) ? (IMG_COUNT-1) : index - 1'b1;
                timer <= {TW{1'b0}};
            end else if (play_en && !emergency) begin
                if (timer == SLIDE_CLKS[TW-1:0] - 1'b1) begin
                    timer      <= {TW{1'b0}};
                    index      <= (index >= IMG_COUNT-1) ? 8'd0 : index + 1'b1;
                    slide_tick <= 1'b1;
                end else begin
                    timer <= timer + 1'b1;
                end
            end else begin
                timer <= {TW{1'b0}};
                // 暂停/应急: 索引保持
            end
        end
    end

endmodule
