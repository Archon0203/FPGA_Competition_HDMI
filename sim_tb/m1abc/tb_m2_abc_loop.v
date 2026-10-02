`timescale 1ns/1ps
module tb_m2_abc_loop;
    reg clk=0, rst_n=0;
    always #5 clk = ~clk;
    reg cmd_valid=0, cmd_play=0, cmd_pause=0;
    reg [7:0] cmd_image_id=0;
    reg [15:0] credit_add=0;
    wire cmd_ready;
    wire catalog_valid, descriptor_valid, source_ready, source_busy, source_done, source_error;
    wire [7:0] catalog_count, descriptor_image_id;
    wire [15:0] catalog_epoch, descriptor_width, descriptor_height, credit_level;
    wire packet_start, line_start, line_end, frame_end, data_valid, source_data_ready;
    wire [15:0] frame_id, line_index;
    wire [7:0] image_id;
    wire [31:0] data_word;
    wire tx_valid, tx_last, tx_ready, tx_busy, tx_done;
    wire [31:0] tx_data;
    wire [7:0] tx_sequence;
    reg inject_bad=0;
    wire rx_valid;
    wire [31:0] rx_data = (inject_bad && tx_last) ? (tx_data ^ 32'h1) : tx_data;
    wire rx_last = tx_last;
    wire rx_line_ready = 1'b1;
    wire rx_line_valid, rx_line_start, rx_line_end, rx_frame_end, rx_ready;
    wire [31:0] rx_line_data;
    wire [15:0] rx_frame_id, rx_line_index;
    wire [7:0] rx_image_id, rx_seq;
    wire rx_frame_accept, rx_protocol_error, rx_link_ready;
    wire commit_pixel_valid, commit_boundary, commit_front_valid, commit_error;
    wire [31:0] commit_pixel_data;
    wire [15:0] commit_front_frame, accepted_lines;
    integer boundaries=0, errors=0;

    assign rx_valid = tx_valid;
    assign tx_ready = rx_ready;

    m2_media_line_source #(.IMAGE_WIDTH(640),.IMAGE_HEIGHT(3),.WORDS_PER_LINE(4),.CATALOG_COUNT(4)) u_src (
        .clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),
        .cmd_image_id(cmd_image_id),.cmd_play(cmd_play),.cmd_pause(cmd_pause),.credit_add(credit_add),
        .catalog_valid(catalog_valid),.catalog_count(catalog_count),.catalog_epoch(catalog_epoch),
        .descriptor_valid(descriptor_valid),.descriptor_image_id(descriptor_image_id),
        .descriptor_width(descriptor_width),.descriptor_height(descriptor_height),
        .source_ready(source_ready),.source_busy(source_busy),.source_done(source_done),
        .source_error(source_error),.credit_level(credit_level),
        .packet_start(packet_start),.frame_id(frame_id),.image_id(image_id),.line_index(line_index),
        .line_start(line_start),.line_end(line_end),.frame_end(frame_end),
        .data_valid(data_valid),.data_ready(source_data_ready),.data_word(data_word));

    m2_line_packet_tx #(.PAYLOAD_WORDS(4)) u_tx (
        .clk(clk),.rst_n(rst_n),.line_start(packet_start),.frame_id(frame_id),.image_id(image_id),
        .line_index(line_index),.payload_valid(data_valid),.payload_data(data_word),
        .payload_ready(source_data_ready),.out_valid(tx_valid),.out_data(tx_data),.out_last(tx_last),
        .out_ready(tx_ready),.busy(tx_busy),.packet_done(tx_done),.sequence(tx_sequence));

    m2_line_packet_rx #(.LINE_WORDS(4),.FRAME_LINES(3)) u_rx (
        .clk(clk),.rst_n(rst_n),.in_valid(rx_valid),.in_data(rx_data),.in_last(rx_last),.in_ready(rx_ready),
        .line_valid(rx_line_valid),.line_data(rx_line_data),.line_ready(rx_line_ready),
        .line_start(rx_line_start),.line_end(rx_line_end),.frame_end(rx_frame_end),
        .frame_id(rx_frame_id),.line_index(rx_line_index),.image_id(rx_image_id),
        .frame_accept(rx_frame_accept),.protocol_error(rx_protocol_error),.link_ready(rx_link_ready),
        .expected_sequence(rx_seq));

    m2_frame_commit #(.FRAME_LINES(3)) u_commit (
        .clk(clk),.rst_n(rst_n),.line_valid(rx_line_valid),.line_data(rx_line_data),
        .line_start(rx_line_start),.line_end(rx_line_end),.frame_end(rx_frame_end),
        .line_frame_id(rx_frame_id),.line_index(rx_line_index),.protocol_error(rx_protocol_error),
        .pixel_valid(commit_pixel_valid),.pixel_data(commit_pixel_data),.frame_boundary(commit_boundary),
        .front_valid(commit_front_valid),.front_frame_id(commit_front_frame),
        .commit_error(commit_error),.accepted_lines(accepted_lines));

    always @(posedge clk) begin
        if (commit_boundary) boundaries = boundaries + 1;
        if (rx_protocol_error || commit_error) errors = errors + 1;
    end

    initial begin
        repeat (4) @(posedge clk); rst_n=1;
        repeat (2) @(posedge clk);
        cmd_image_id=2; cmd_play=1; cmd_valid=1; credit_add=16'd8;
        @(posedge clk); cmd_valid=0; cmd_play=0; credit_add=0;
        wait (boundaries >= 1);
        if (!commit_front_valid || commit_front_frame == 0) begin $display("FAIL: first frame not committed"); $fatal; end
        // Reset is the defined recovery boundary after a lost packet in M2.
        inject_bad=1;
        repeat (80) @(posedge clk);
        if (errors == 0) begin $display("FAIL: CRC error not detected"); $fatal; end
        if (boundaries != 1) begin $display("FAIL: bad stream polluted front"); $fatal; end
        rst_n=0; repeat (3) @(posedge clk); rst_n=1;
        boundaries=0; errors=0; inject_bad=0;
        cmd_image_id=1; cmd_play=1; cmd_valid=1; credit_add=16'd4;
        @(posedge clk); cmd_valid=0; cmd_play=0; credit_add=0;
        wait (boundaries >= 1);
        $display("PASS: m2 abc loop boundaries=%0d errors_recovered=%0d", boundaries, errors);
        $finish;
    end
endmodule
