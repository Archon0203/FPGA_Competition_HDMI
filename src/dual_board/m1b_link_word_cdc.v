// ============================================================================
// M1B source-synchronous capture -> system-domain FIFO boundary.
// Data and sideband are captured together in link_clk and crossed through a
// Gray-pointer async FIFO. This freezes the CDC contract used by the later
// wide GPIO data plane. Per-pin delay/deskew is intentionally NOT claimed here;
// that requires a concrete 40-pin assignment, cable, P&R and board timing gate.
// ============================================================================
module m1b_link_word_cdc #(
    parameter integer ADDR_WIDTH = 4
)(
    input  wire        link_clk,
    input  wire        link_rst_n,
    input  wire        link_valid,
    input  wire [31:0] link_data,
    input  wire        link_sof,
    input  wire        link_eol,
    input  wire        link_eof,
    output wire        link_ready,
    output reg         overflow_sticky,

    input  wire        sys_clk,
    input  wire        sys_rst_n,
    output wire        sys_valid,
    output wire [31:0] sys_data,
    output wire        sys_sof,
    output wire        sys_eol,
    output wire        sys_eof,
    input  wire        sys_ready
);
    wire full, empty;
    wire [34:0] fifo_dout;
    wire wr_en = link_valid && link_ready;
    wire rd_en = sys_valid && sys_ready;

    assign link_ready = ~full;
    assign sys_valid  = ~empty;
    assign {sys_eof, sys_eol, sys_sof, sys_data} = fifo_dout;

    async_fifo #(.DATA_WIDTH(35), .ADDR_WIDTH(ADDR_WIDTH)) u_fifo (
        .wr_clk(link_clk), .wr_rst_n(link_rst_n), .wr_en(wr_en),
        .din({link_eof, link_eol, link_sof, link_data}),
        .rd_clk(sys_clk), .rd_rst_n(sys_rst_n), .rd_en(rd_en),
        .dout(fifo_dout), .full(full), .empty(empty));

    always @(posedge link_clk or negedge link_rst_n) begin
        if (!link_rst_n)
            overflow_sticky <= 1'b0;
        else if (link_valid && full)
            overflow_sticky <= 1'b1;
    end
endmodule
