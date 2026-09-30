// Byte-stream CDC used between a physical TF/provider clock and media service.
// The FIFO handshake is explicit: source data is accepted only when src_ready
// is high, and destination data remains available until dst_ready is high.
module m1a_provider_cdc #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input  wire                   src_clk,
    input  wire                   src_rst_n,
    input  wire                   src_valid,
    input  wire [DATA_WIDTH-1:0]  src_data,
    output wire                   src_ready,
    output reg                    src_overflow,
    input  wire                   dst_clk,
    input  wire                   dst_rst_n,
    output wire                   dst_valid,
    output wire [DATA_WIDTH-1:0]  dst_data,
    input  wire                   dst_ready
);
    wire full, empty;
    wire wr_en = src_valid & src_ready;
    wire rd_en = dst_valid & dst_ready;

    assign src_ready = ~full;
    assign dst_valid = ~empty;

    async_fifo #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_fifo (
        .wr_clk(src_clk), .wr_rst_n(src_rst_n), .wr_en(wr_en), .din(src_data),
        .rd_clk(dst_clk), .rd_rst_n(dst_rst_n), .rd_en(rd_en), .dout(dst_data),
        .full(full), .empty(empty)
    );

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) src_overflow <= 1'b0;
        else if (src_valid & full) src_overflow <= 1'b1;
    end
endmodule
