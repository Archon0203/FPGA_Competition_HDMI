// M2 Master receive/commit core. Packet words arrive after physical CDC.
// frame_boundary is synchronized to clk by the integrating display top.
module m2_master_line_core #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480,
    parameter [20:0] BASE_A = 21'd0,
    parameter [20:0] BASE_B = 21'd307200
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        packet_valid,
    input  wire [31:0] packet_data,
    input  wire        packet_last,
    output wire        packet_ready,
    output wire        mem_wr_valid,
    output wire [20:0] mem_wr_addr,
    output wire [31:0] mem_wr_data,
    input  wire        mem_wr_ready,
    input  wire        frame_boundary,
    output wire [20:0] front_base,
    output wire        front_valid,
    output wire [15:0] front_frame_id,
    output wire [7:0]  front_image_id,
    output wire        pending_swap,
    output wire        commit_pulse,
    output wire        commit_error,
    output wire        protocol_error,
    output wire        link_ready
);
    wire line_valid, line_ready, line_start, line_end, frame_end;
    wire [31:0] line_data;
    wire [15:0] frame_id, line_index;
    wire [7:0] image_id;

    m2_line_packet_rx #(.LINE_WORDS(WIDTH), .FRAME_LINES(HEIGHT)) u_rx (
        .clk(clk), .rst_n(rst_n),
        .in_valid(packet_valid), .in_data(packet_data),
        .in_last(packet_last), .in_ready(packet_ready),
        .line_valid(line_valid), .line_data(line_data),
        .line_ready(line_ready), .line_start(line_start),
        .line_end(line_end), .frame_end(frame_end),
        .frame_id(frame_id), .line_index(line_index),
        .image_id(image_id), .frame_accept(),
        .protocol_error(protocol_error), .link_ready(link_ready),
        .expected_sequence());

    m2_master_frame_store #(
        .WIDTH(WIDTH), .HEIGHT(HEIGHT), .BASE_A(BASE_A), .BASE_B(BASE_B)
    ) u_store (
        .clk(clk), .rst_n(rst_n),
        .line_valid(line_valid), .line_data(line_data),
        .line_start(line_start), .line_end(line_end),
        .frame_end(frame_end), .line_frame_id(frame_id),
        .line_image_id(image_id), .line_index(line_index),
        .line_ready(line_ready), .protocol_error(protocol_error),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data), .mem_wr_ready(mem_wr_ready),
        .frame_boundary(frame_boundary), .front_base(front_base),
        .front_valid(front_valid), .front_frame_id(front_frame_id),
        .front_image_id(front_image_id), .pending_swap(pending_swap),
        .commit_pulse(commit_pulse), .commit_error(commit_error));
endmodule
