// M2 integrated A/B/C diagnostic used in both long-lived TD projects.
// It exercises the media command/descriptor boundary, line packet TX/RX,
// CRC/sequence, RX backpressure and frame-boundary commit without consuming
// the frozen HDMI rollback path.  The real TF provider and source-synchronous
// GPIO pins replace this local loopback at the M2 board-data gate.
module m2_abc_loopback_diag #(
    parameter integer FRAME_LINES = 4,
    parameter integer WORDS_PER_LINE = 4
)(
    input  wire clk,
    input  wire rst_n,
    output wire pass,
    output wire busy,
    output wire error,
    output wire frame_boundary
);
    reg [2:0] boot;
    reg started;
    wire cmd_valid = (boot == 3'd3) && !started;
    wire cmd_ready;
    wire source_data_ready;
    wire [15:0] credit_level;
    wire packet_start, data_valid;
    wire [15:0] frame_id, line_index;
    wire [7:0] image_id;
    wire [31:0] data_word;
    wire src_catalog_valid, src_desc_valid, src_ready, src_busy, src_done, src_error;
    wire [7:0] src_catalog_count, src_desc_image;
    wire [15:0] src_catalog_epoch, src_desc_width, src_desc_height;
    wire tx_valid, tx_last, tx_ready, tx_busy, tx_done;
    wire [31:0] tx_data;
    wire [7:0] tx_sequence;
    wire rx_ready, rx_line_valid, rx_line_start, rx_line_end, rx_frame_end;
    wire [31:0] rx_line_data;
    wire [15:0] rx_frame_id, rx_line_index;
    wire [7:0] rx_image_id, rx_expected_seq;
    wire rx_frame_accept, rx_protocol_error, rx_link_ready;
    wire commit_pixel_valid, commit_error;
    wire [31:0] commit_pixel_data;
    wire commit_front_valid;
    wire [15:0] commit_front_frame, accepted_lines;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin boot <= 0; started <= 1'b0; end
        else begin
            if (boot != 3'd3) boot <= boot + 1'b1;
            if (cmd_valid && cmd_ready) started <= 1'b1;
        end
    end

    m2_media_line_source #(
        .IMAGE_WIDTH(640), .IMAGE_HEIGHT(FRAME_LINES),
        .WORDS_PER_LINE(WORDS_PER_LINE), .CATALOG_COUNT(4)
    ) u_source (
        .clk(clk), .rst_n(rst_n), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_image_id(8'd0), .cmd_play(1'b1), .cmd_pause(1'b0), .credit_add(16'd1),
        .catalog_valid(src_catalog_valid), .catalog_count(src_catalog_count), .catalog_epoch(src_catalog_epoch),
        .descriptor_valid(src_desc_valid), .descriptor_image_id(src_desc_image),
        .descriptor_width(src_desc_width), .descriptor_height(src_desc_height),
        .source_ready(src_ready), .source_busy(src_busy), .source_done(src_done),
        .source_error(src_error), .credit_level(credit_level),
        .packet_start(packet_start), .frame_id(frame_id), .image_id(image_id),
        .line_index(line_index), .line_start(), .line_end(), .frame_end(),
        .data_valid(data_valid), .data_ready(source_data_ready), .data_word(data_word));

    m2_line_packet_tx #(.PAYLOAD_WORDS(WORDS_PER_LINE)) u_tx (
        .clk(clk), .rst_n(rst_n), .line_start(packet_start),
        .frame_id(frame_id), .image_id(image_id), .line_index(line_index),
        .payload_valid(data_valid), .payload_data(data_word), .payload_ready(source_data_ready),
        .out_valid(tx_valid), .out_data(tx_data), .out_last(tx_last), .out_ready(tx_ready),
        .busy(tx_busy), .packet_done(tx_done), .sequence(tx_sequence));

    m2_line_packet_rx #(.LINE_WORDS(WORDS_PER_LINE), .FRAME_LINES(FRAME_LINES)) u_rx (
        .clk(clk), .rst_n(rst_n), .in_valid(tx_valid), .in_data(tx_data), .in_last(tx_last), .in_ready(rx_ready),
        .line_valid(rx_line_valid), .line_data(rx_line_data), .line_ready(1'b1),
        .line_start(rx_line_start), .line_end(rx_line_end), .frame_end(rx_frame_end),
        .frame_id(rx_frame_id), .line_index(rx_line_index), .image_id(rx_image_id),
        .frame_accept(rx_frame_accept), .protocol_error(rx_protocol_error), .link_ready(rx_link_ready),
        .expected_sequence(rx_expected_seq));
    assign tx_ready = rx_ready;

    m2_frame_commit #(.FRAME_LINES(FRAME_LINES)) u_commit (
        .clk(clk), .rst_n(rst_n), .line_valid(rx_line_valid), .line_data(rx_line_data),
        .line_start(rx_line_start), .line_end(rx_line_end), .frame_end(rx_frame_end),
        .line_frame_id(rx_frame_id), .line_index(rx_line_index), .protocol_error(rx_protocol_error),
        .pixel_valid(commit_pixel_valid), .pixel_data(commit_pixel_data),
        .frame_boundary(frame_boundary), .front_valid(commit_front_valid),
        .front_frame_id(commit_front_frame), .commit_error(commit_error), .accepted_lines(accepted_lines));

    assign pass = commit_front_valid && !rx_protocol_error && !commit_error;
    assign busy = tx_busy || (credit_level != 0);
    assign error = rx_protocol_error || commit_error;
endmodule
