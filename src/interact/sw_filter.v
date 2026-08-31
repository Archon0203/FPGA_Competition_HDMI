// ================================================================
// 模块   : sw_filter
// 功能   : 4 路拨码开关消抖 + 电平变化边沿检测。
//           raw = ACTIVE_LOW ? ~sw_in : sw_in   (逻辑"ON"为 1)
//           连续 CNT_MAX 拍稳定后输出稳定逻辑电平 sw_out。
//           电平变化(任意方向)产生单拍脉冲 sw_changed, 供状态机响应。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效)  : 系统时钟与复位
//   - sw_in[3:0]           : 原始拨码输入(有抖动)
//   - sw_out[3:0]          : 消抖后的逻辑电平(1=ON)
//   - sw_changed[3:0]      : 电平变化事件(单拍脉冲, 高有效)
// 参数:
//   - CNT_MAX              : 消抖计数阈值(时钟数), 默认 20
//   - ACTIVE_LOW           : 拨码有效电平, 1=低有效(板卡默认), 0=高有效
// 时钟域: clk 为交互/系统时钟域(clk_sys)。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T18 实现。
// ================================================================

module sw_filter #(
    parameter integer CNT_MAX    = 20,
    parameter        ACTIVE_LOW = 1'b1
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] sw_in,
    output wire [3:0] sw_out,
    output wire [3:0] sw_changed
);

    localparam integer CW = (CNT_MAX > 1) ? $clog2(CNT_MAX + 1) : 1;

    wire [3:0] raw_async = ACTIVE_LOW ? ~sw_in : sw_in;

    reg [3:0] sw_sync1, sw_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sw_sync1 <= 4'b0000;
            sw_sync2 <= 4'b0000;
        end else begin
            sw_sync1 <= raw_async;
            sw_sync2 <= sw_sync1;
        end
    end
    wire [3:0] raw = sw_sync2;

    wire [3:0] sw_stable;
    reg  [3:0] prev;

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : gen_chan
            reg [CW-1:0] cnt;
            reg          st;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    cnt <= {CW{1'b0}};
                    st  <= 1'b0;
                end else if (raw[g] != st) begin
                    if (cnt == CNT_MAX[CW-1:0]) begin
                        st  <= raw[g];
                        cnt <= {CW{1'b0}};
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end else begin
                    cnt <= {CW{1'b0}};
                end
            end
            assign sw_stable[g] = st;
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) prev <= 4'b0000;
        else        prev <= sw_stable;
    end

    assign sw_out     = sw_stable;
    assign sw_changed = sw_stable ^ prev;

endmodule
