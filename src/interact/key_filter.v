// ================================================================
// 模块   : key_filter
// 功能   : 4 路按键消抖 + 按下边沿检测。
//           raw = ACTIVE_LOW ? ~key_in : key_in   (逻辑"按下"为 1)
//           消抖: 连续 CNT_MAX 拍稳定后输出稳定逻辑电平 key_out。
//           边沿: key_event 为 key_out 上跳沿(按下)的单拍脉冲。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效)  : 系统时钟与复位
//   - key_in[3:0]          : 原始按键输入(有抖动)
//   - key_out[3:0]         : 消抖后的逻辑电平(1=被按下)
//   - key_event[3:0]       : 按下事件(单拍脉冲, 高有效)
// 参数:
//   - CNT_MAX              : 消抖计数阈值(时钟数), 默认 20
//   - ACTIVE_LOW           : 按键有效电平, 1=低有效(板卡默认), 0=高有效
// 时钟域: clk 为交互/系统时钟域(clk_sys)。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T17 实现。
// ================================================================

module key_filter #(
    parameter integer CNT_MAX    = 20,
    parameter        ACTIVE_LOW = 1'b1
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] key_in,
    output wire [3:0] key_out,
    output wire [3:0] key_event
);

    localparam integer CW = (CNT_MAX > 1) ? $clog2(CNT_MAX + 1) : 1;

    // 逻辑按下电平(归一化为高有效)
    wire [3:0] raw = ACTIVE_LOW ? ~key_in : key_in;

    wire [3:0] stable;    // 消抖后的稳定电平(由 generate 连续赋值)
    reg [3:0] prev;       // 上一拍稳定电平

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
            assign stable[g] = st;
        end
    endgenerate

    // 边沿检测: key_event = key_out 上跳沿(按下)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) prev <= 4'b0000;
        else        prev <= stable;
    end

    assign key_out   = stable;
    assign key_event = stable & ~prev;

endmodule
