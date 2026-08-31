// ================================================================
// 模块   : sd_spi
// 功能   : SD/SPI 字节级主控制器(SPI Mode 0: CPOL=0, CPHA=0)。
//           start 拉起后发送 din 并同步接收对端字节; 数据 MSB 先发。
//           sclk 由 clk 分频产生; 上升沿采样 miso, 下降沿更新 mosi。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 系统/SD 时钟
//   - start               : 单拍启动脉冲
//   - din[7:0]            : 待发送字节
//   - busy / done         : 忙标志 / 完成单拍
//   - dout[7:0]           : 接收字节
//   - mosi / sclk         : 输出(主出从入/时钟)
//   - miso                : 输入(主入从出)
// 参数:
//   - CLK_DIV             : sclk 半周期 = CLK_DIV 个 clk, 默认 2
// 时钟域: clk 为 SD 读卡时钟域(clk_sdo 或 clk_sys)。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T4 实现。
// ================================================================

module sd_spi #(
    parameter integer CLK_DIV = 2
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [7:0]  din,
    output wire        busy,
    output wire        done,
    output wire [7:0]  dout,
    output reg         mosi,
    output wire        sclk,
    input  wire        miso
);

    localparam integer DW = $clog2(2 * CLK_DIV);
    localparam [1:0] S_IDLE = 2'd0, S_RUN = 2'd1, S_DONE = 2'd2;

    reg [DW-1:0] div;
    reg          busy_r, done_r;
    reg  [1:0]   state;
    reg  [7:0]   tx, rx, dout_r;
    reg  [2:0]   bit_idx;
    reg          sclk_q;         // 上一拍 sclk(用于沿检测)

    // 分频产生 sclk: div<CLK_DIV 为低, div>=CLK_DIV 为高
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) div <= {DW{1'b0}};
        else if (busy_r) begin
            if (div == (2*CLK_DIV-1)) div <= {DW{1'b0}};
            else                      div <= div + 1'b1;
        end else begin
            div <= {DW{1'b0}};
        end
    end
    assign sclk = (div >= CLK_DIV);

    wire rise = sclk && !sclk_q;
    wire fall = !sclk && sclk_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            busy_r   <= 1'b0;
            done_r   <= 1'b0;
            tx       <= 8'd0;
            rx       <= 8'd0;
            dout_r   <= 8'd0;
            bit_idx  <= 3'd0;
            mosi     <= 1'b0;
            sclk_q   <= 1'b0;
        end else begin
            sclk_q <= sclk;
            case (state)
                S_IDLE: begin
                    done_r <= 1'b0;
                    if (start) begin
                        tx      <= din;
                        rx      <= 8'd0;
                        dout_r  <= 8'd0;
                        bit_idx <= 3'd0;
                        mosi    <= din[7];
                        state   <= S_RUN;
                        busy_r  <= 1'b1;
                    end
                end
                S_RUN: begin
                    // 上升沿: 采样 MISO
                    if (rise) rx <= {rx[6:0], miso};
                    // 下降沿: 移位/完成
                    if (fall) begin
                        if (bit_idx == 3'd7) begin
                            state  <= S_DONE;
                            busy_r <= 1'b0;
                            done_r <= 1'b1;
                            dout_r <= rx;
                        end else begin
                            mosi    <= tx[6];
                            tx      <= {tx[6:0], 1'b0};
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                end
                S_DONE: begin
                    done_r <= 1'b0;
                    state  <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    assign busy = busy_r;
    assign done = done_r;
    assign dout = dout_r;

endmodule
