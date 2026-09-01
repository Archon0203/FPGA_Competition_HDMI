// ================================================================
// 模块   : sdram_arbiter
// 功能   : P0-07 framebuffer 抽象 SDRAM 仲裁器。
//           - writer 写请求源 + line_prefetcher 读请求源
//           - 同周期最多向下游发出一个命令，严格 read-priority
//           - 读 response 只返回 line_prefetcher
//           - 追踪 outstanding read，丢弃/报告无对应请求的 response
//           - 不直接例化 APUG011；P1 由 sdram_adapter 接官方 controller
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-31
// 版本   : v1.1  (150 MHz timing cleanup candidate; rerun UNIT regression required)
// 时钟域 : P0 抽象 memory/request 时钟域
//
// 设计约束：
//   1) framebuffer_writer 与 line_prefetcher 是当前仅有 request source。
//   2) 显示读优先于后台写；显示链不能因图片加载而断流。
//   3) 下游 read response 必须保持 accepted request 顺序。
//   4) 该模块不直接写 line_buffer；response 只回 line_prefetcher。
// ================================================================

module sdram_arbiter #(
    parameter integer MAX_READ_OUTSTANDING = 16
) (
    input  wire         clk,
    input  wire         rst_n,

    // ---------------- Writer source ----------------
    input  wire         wr_valid,
    input  wire [20:0]  wr_addr,
    input  wire [31:0]  wr_data,
    output wire         wr_ready,

    // ---------------- Prefetch read source ----------------
    input  wire         rd_valid,
    input  wire [20:0]  rd_addr,
    output wire         rd_ready,
    output wire         rd_rvalid,
    output wire [31:0]  rd_rdata,

    // ---------------- Downstream abstract memory ----------------
    output wire         mem_wr_valid,
    output wire [20:0]  mem_wr_addr,
    output wire [31:0]  mem_wr_data,
    input  wire         mem_wr_ready,

    output wire         mem_rd_valid,
    output wire [20:0]  mem_rd_addr,
    input  wire         mem_rd_ready,
    input  wire         mem_rvalid,
    input  wire [31:0]  mem_rdata,

    // ---------------- Status/debug ----------------
    output reg          protocol_error,
    output reg          contention_seen,
    output wire [15:0]  rd_outstanding_debug,
    output reg  [31:0]  read_accept_count_debug,
    output reg  [31:0]  write_accept_count_debug
);

    reg [15:0] rd_outstanding;

    wire read_credit = (MAX_READ_OUTSTANDING > 0) &&
                       (rd_outstanding < MAX_READ_OUTSTANDING);

    // Strict display-read priority. A pending rd_valid blocks writer command
    // issue even if the downstream read side happens to stall this cycle.
    wire select_read = rd_valid;

    assign mem_rd_valid = select_read && read_credit;
    assign mem_rd_addr  = rd_addr;
    assign rd_ready     = select_read && read_credit && mem_rd_ready;

    assign mem_wr_valid = wr_valid && !select_read;
    assign mem_wr_addr  = wr_addr;
    assign mem_wr_data  = wr_data;
    assign wr_ready     = !select_read && mem_wr_ready;

    wire rd_accept = mem_rd_valid && mem_rd_ready;
    wire wr_accept = mem_wr_valid && mem_wr_ready;

    // A zero-latency downstream model is legal: a response on the same cycle
    // as the first accepted request is therefore accepted.
    wire response_legal = mem_rvalid &&
                          ((rd_outstanding != 16'd0) || rd_accept);

    assign rd_rvalid = response_legal;
    assign rd_rdata  = mem_rdata;

    // The request path is already credit-gated by read_credit, therefore an
    // accepted read can never increase rd_outstanding beyond the configured
    // limit.  Keep the sequential update as a 2-bit event case instead of a
    // 17-bit add/subtract/compare cone.  This is functionally equivalent but
    // removes a non-functional timing path from downstream ready back into the
    // sticky protocol_error register at 150 MHz.
    assign rd_outstanding_debug = rd_outstanding;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_outstanding          <= 16'd0;
            protocol_error          <= 1'b0;
            contention_seen         <= 1'b0;
            read_accept_count_debug <= 32'd0;
            write_accept_count_debug<= 32'd0;
        end else begin
            if (wr_valid && rd_valid)
                contention_seen <= 1'b1;

            if (rd_accept)
                read_accept_count_debug <= read_accept_count_debug + 32'd1;
            if (wr_accept)
                write_accept_count_debug <= write_accept_count_debug + 32'd1;

            // There must never be two accepted commands in one cycle.
            if (rd_accept && wr_accept)
                protocol_error <= 1'b1;

            // Drop unsolicited responses instead of forwarding garbage into the
            // display path; keep a sticky error for board/debug observability.
            if (mem_rvalid && !response_legal)
                protocol_error <= 1'b1;

            case ({rd_accept, response_legal})
                2'b10: rd_outstanding <= rd_outstanding + 16'd1;
                2'b01: rd_outstanding <= rd_outstanding - 16'd1;
                default: rd_outstanding <= rd_outstanding;
            endcase
        end
    end

endmodule
