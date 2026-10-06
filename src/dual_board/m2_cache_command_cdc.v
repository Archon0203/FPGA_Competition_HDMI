// One outstanding cache query. FIFO FWFT data is consumed on the same edge
// as rd_en; never register rd_en and accidentally consume a command twice.
// Reset both halves together if HDMI recovery restarts the display domain.
module m2_cache_command_cdc(
    input wire ctrl_clk, media_clk, rst_n,
    input wire ctrl_query_valid, input wire [7:0] ctrl_query_id,
    output wire ctrl_query_ready,
    output wire ctrl_reply_valid, ctrl_reply_hit, input wire ctrl_reply_ready,
    output wire media_query_valid, output wire [7:0] media_query_id,
    input wire media_query_ready,
    input wire media_reply_valid, media_reply_hit, output wire media_reply_ready
);
    wire query_full, query_empty, reply_full, reply_empty;
    assign ctrl_query_ready=!query_full;
    assign media_query_valid=!query_empty;
    assign media_reply_ready=!reply_full;
    assign ctrl_reply_valid=!reply_empty;
    async_fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(2)) u_query(
        .wr_clk(ctrl_clk), .wr_rst_n(rst_n),
        .wr_en(ctrl_query_valid && ctrl_query_ready), .din(ctrl_query_id),
        .rd_clk(media_clk), .rd_rst_n(rst_n),
        .rd_en(media_query_valid && media_query_ready), .dout(media_query_id),
        .full(query_full), .empty(query_empty));
    async_fifo #(.DATA_WIDTH(1), .ADDR_WIDTH(2)) u_reply(
        .wr_clk(media_clk), .wr_rst_n(rst_n),
        .wr_en(media_reply_valid && media_reply_ready), .din(media_reply_hit),
        .rd_clk(ctrl_clk), .rd_rst_n(rst_n),
        .rd_en(ctrl_reply_valid && ctrl_reply_ready), .dout(ctrl_reply_hit),
        .full(reply_full), .empty(reply_empty));
endmodule
