// M2 B-line TX wrapper.  Keeps the application-facing line source independent
// from the transport packet format frozen by m1b_line_packetizer.
module m2_line_packet_tx #(
    parameter integer PAYLOAD_WORDS = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        line_start,
    input  wire [15:0] frame_id,
    input  wire [7:0]  image_id,
    input  wire [15:0] line_index,
    input  wire        payload_valid,
    input  wire [31:0] payload_data,
    output wire        payload_ready,
    output wire        out_valid,
    output wire [31:0] out_data,
    output wire        out_last,
    input  wire        out_ready,
    output wire        busy,
    output wire        packet_done,
    output wire [7:0]  sequence
);
    m1b_line_packetizer #(.PAYLOAD_WORDS(PAYLOAD_WORDS)) u_packetizer (
        .clk(clk), .rst_n(rst_n), .start(line_start),
        .frame_id(frame_id), .image_id(image_id), .line_index(line_index),
        .in_valid(payload_valid), .in_data(payload_data), .in_ready(payload_ready),
        .out_valid(out_valid), .out_data(out_data), .out_last(out_last),
        .out_ready(out_ready), .busy(busy), .packet_done(packet_done),
        .sequence(sequence));
endmodule
