// ================================================================
// 模块   : reset_gen
// 功能   : 上电/异步复位同步释放电路。
//           async_rst_n 拉低立即同步置位复位(异步有效);
//           释放后保持 RST_CLKS 个时钟周期再同步释放, 避免亚稳态/毛刺。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk                 : 目标时钟域时钟
//   - async_rst_n         : 异步复位(低有效, 可由上电检测/外部按键)
//   - sync_rst_n          : 同步复位输出(低有效)
// 参数:
//   - RST_CLKS            : 释放延迟时钟数, 默认 100
// 时钟域: clk 为目标时钟域; 每个时钟域各例化一个实例。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡实现。
// ================================================================

module reset_gen #(
    parameter integer RST_CLKS = 100
)(
    input  wire clk,
    input  wire async_rst_n,
    output wire sync_rst_n
);

    localparam integer CW = $clog2(RST_CLKS + 1);

    reg [CW-1:0] cnt;
    reg          in_reset;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            cnt      <= {CW{1'b0}};
            in_reset <= 1'b1;
        end else if (in_reset) begin
            if (cnt == RST_CLKS[CW-1:0] - 1'b1) begin
                cnt      <= {CW{1'b0}};
                in_reset <= 1'b0;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

    assign sync_rst_n = ~in_reset;

endmodule
