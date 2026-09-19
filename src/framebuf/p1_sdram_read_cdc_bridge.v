// ================================================================
// Module  : p1_sdram_read_cdc_bridge
// Purpose : Ordered read-request/response CDC between the 25 MHz display
//           domain and the 150 MHz APUG011/sdram_arbiter domain.
//
// Design:
//   pixel request -> async FIFO -> registered SDR request slice -> arbiter
//   arbiter response -> async FIFO -> pixel response
//
// The registered SDR request slice intentionally removes a combinational path
// from async-FIFO memory output into the 150 MHz arbiter/adapter timing cone.
// line_prefetcher bounds outstanding reads, so the response FIFO cannot grow
// without bound under the intended contract.
// ================================================================

module p1_sdram_read_cdc_bridge #(
    parameter integer REQ_FIFO_ADDR_WIDTH  = 4,
    parameter integer RESP_FIFO_ADDR_WIDTH = 4
) (
    // Pixel/display domain.
    input  wire        pix_clk,
    input  wire        pix_rst_n,
    input  wire        pix_mem_rd_valid,
    input  wire [20:0] pix_mem_rd_addr,
    output wire        pix_mem_rd_ready,
    output wire        pix_mem_rvalid,
    output wire [31:0] pix_mem_rdata,

    // SDRAM domain.
    input  wire        sdr_clk,
    input  wire        sdr_rst_n,
    output wire        sdr_mem_rd_valid,
    output wire [20:0] sdr_mem_rd_addr,
    input  wire        sdr_mem_rd_ready,
    input  wire        sdr_mem_rvalid,
    input  wire [31:0] sdr_mem_rdata,

    output reg         protocol_error
);

    // ------------------------------------------------------------
    // Request FIFO: pixel -> SDRAM
    // ------------------------------------------------------------
    wire [20:0] req_fifo_dout;
    wire        req_fifo_full;
    wire        req_fifo_empty;

    wire req_fifo_wr_en = pix_mem_rd_valid && pix_mem_rd_ready;
    assign pix_mem_rd_ready = !req_fifo_full;

    reg         req_stage_valid;
    reg  [20:0] req_stage_addr;

    wire req_stage_accept = req_stage_valid && sdr_mem_rd_ready;
    wire req_fifo_rd_en = !req_fifo_empty &&
                          (!req_stage_valid || req_stage_accept);

    async_fifo #(
        .DATA_WIDTH(21),
        .ADDR_WIDTH(REQ_FIFO_ADDR_WIDTH)
    ) u_req_fifo (
        .wr_clk   (pix_clk),
        .wr_rst_n (pix_rst_n),
        .wr_en    (req_fifo_wr_en),
        .din      (pix_mem_rd_addr),
        .rd_clk   (sdr_clk),
        .rd_rst_n (sdr_rst_n),
        .rd_en    (req_fifo_rd_en),
        .dout     (req_fifo_dout),
        .full     (req_fifo_full),
        .empty    (req_fifo_empty)
    );

    assign sdr_mem_rd_valid = req_stage_valid;
    assign sdr_mem_rd_addr  = req_stage_addr;

    always @(posedge sdr_clk or negedge sdr_rst_n) begin
        if (!sdr_rst_n) begin
            req_stage_valid <= 1'b0;
            req_stage_addr  <= 21'd0;
        end else begin
            if (req_fifo_rd_en) begin
                req_stage_valid <= 1'b1;
                req_stage_addr  <= req_fifo_dout;
            end else if (req_stage_accept) begin
                req_stage_valid <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------
    // Response FIFO: SDRAM -> pixel
    // ------------------------------------------------------------
    wire [31:0] resp_fifo_dout;
    wire        resp_fifo_full;
    wire        resp_fifo_empty;

    wire resp_fifo_wr_en = sdr_mem_rvalid && !resp_fifo_full;
    wire resp_fifo_rd_en = !resp_fifo_empty;

    async_fifo #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(RESP_FIFO_ADDR_WIDTH)
    ) u_resp_fifo (
        .wr_clk   (sdr_clk),
        .wr_rst_n (sdr_rst_n),
        .wr_en    (resp_fifo_wr_en),
        .din      (sdr_mem_rdata),
        .rd_clk   (pix_clk),
        .rd_rst_n (pix_rst_n),
        .rd_en    (resp_fifo_rd_en),
        .dout     (resp_fifo_dout),
        .full     (resp_fifo_full),
        .empty    (resp_fifo_empty)
    );

    assign pix_mem_rvalid = !resp_fifo_empty;
    assign pix_mem_rdata  = resp_fifo_dout;

    // A returned word cannot be backpressured. Overflow is therefore a hard
    // contract violation and is kept sticky for TD/board diagnostics.
    always @(posedge sdr_clk or negedge sdr_rst_n) begin
        if (!sdr_rst_n)
            protocol_error <= 1'b0;
        else if (sdr_mem_rvalid && resp_fifo_full)
            protocol_error <= 1'b1;
    end

endmodule
