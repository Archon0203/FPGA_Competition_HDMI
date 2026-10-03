// Media-domain writer to SDRAM-domain write port. Completion is fenced by
// emptying the FIFO and waiting until the SDRAM adapter accepts a new write.
module m2_media_write_cdc #(
    parameter integer FIFO_ADDR_WIDTH = 5
)(
    input  wire        media_clk,
    input  wire        media_rst_n,
    input  wire        media_wr_valid,
    input  wire [20:0] media_wr_addr,
    input  wire [31:0] media_wr_data,
    output wire        media_wr_ready,
    input  wire        media_done,
    output reg         sdr_fenced,
    input  wire        sdr_clk,
    input  wire        sdr_rst_n,
    output wire        sdr_wr_valid,
    output wire [20:0] sdr_wr_addr,
    output wire [31:0] sdr_wr_data,
    input  wire        sdr_wr_ready,
    input  wire        sdr_adapter_idle
);
    wire full, empty;
    wire [52:0] rd_word;
    reg done_latched;
    reg done_sync1, done_sync2;

    async_fifo #(.DATA_WIDTH(53), .ADDR_WIDTH(FIFO_ADDR_WIDTH)) u_fifo (
        .wr_clk(media_clk), .wr_rst_n(media_rst_n),
        .wr_en(media_wr_valid && media_wr_ready),
        .din({media_wr_addr, media_wr_data}), .full(full),
        .rd_clk(sdr_clk), .rd_rst_n(sdr_rst_n),
        .rd_en(sdr_wr_valid && sdr_wr_ready),
        .dout(rd_word), .empty(empty));
    assign media_wr_ready = !full;
    assign sdr_wr_valid = !empty;
    assign {sdr_wr_addr, sdr_wr_data} = rd_word;

    always @(posedge media_clk or negedge media_rst_n) begin
        if (!media_rst_n) begin
            done_latched <= 0;
        end else begin
            if (media_done) done_latched <= 1;
        end
    end

    always @(posedge sdr_clk or negedge sdr_rst_n) begin
        if (!sdr_rst_n) begin
            done_sync1 <= 0;
            done_sync2 <= 0;
            sdr_fenced <= 0;
        end else begin
            done_sync1 <= done_latched;
            done_sync2 <= done_sync1;
            if (done_sync2 && empty && sdr_adapter_idle)
                sdr_fenced <= 1;
        end
    end
endmodule
