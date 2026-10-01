// ============================================================================
// Synthesizable M1 B-line contract self-test.
// It does NOT prove the future wide GPIO physical link; it proves that the
// frozen line packet header/sequence/CRC formatter and checker agree in logic.
// Physical PRBS/deskew is a separate M2-B0 board gate once the wide cable/pin
// map is available.
// ============================================================================
module m1b_packet_selftest #(
    parameter integer TEST_PACKETS = 16,
    parameter integer PAYLOAD_WORDS = 4,
    parameter integer TIMEOUT_CYCLES = 200000
)(
    input  wire clk,
    input  wire rst_n,
    output reg  done,
    output reg  pass,
    output reg  fail,
    output reg [15:0] good_packets
);
    reg start;
    wire busy;
    wire packet_done;
    wire [7:0] sequence;
    wire payload_ready;
    wire [31:0] prbs_data;
    wire out_valid;
    wire [31:0] out_data;
    wire out_last;
    wire checker_ok;
    wire checker_error;
    wire checker_ready;
    wire [7:0] expected_sequence;
    wire [15:0] last_frame_id, last_line_index;
    wire [7:0] last_image_id;
    reg [31:0] timeout_count;
    reg [15:0] launched_packets;

    m1b_prbs31 u_prbs (
        .clk(clk), .rst_n(rst_n), .enable(payload_ready), .data(prbs_data));

    m1b_line_packetizer #(.PAYLOAD_WORDS(PAYLOAD_WORDS)) u_packetizer (
        .clk(clk), .rst_n(rst_n), .start(start),
        .frame_id(launched_packets), .image_id(8'h5A),
        .line_index(launched_packets),
        .in_valid(1'b1), .in_data(prbs_data), .in_ready(payload_ready),
        .out_valid(out_valid), .out_data(out_data), .out_last(out_last),
        .out_ready(checker_ready), .busy(busy), .packet_done(packet_done),
        .sequence(sequence));

    m1b_line_packet_checker u_checker (
        .clk(clk), .rst_n(rst_n), .in_valid(out_valid), .in_data(out_data),
        .in_last(out_last), .in_ready(checker_ready),
        .packet_ok(checker_ok), .packet_error(checker_error),
        .expected_sequence(expected_sequence), .last_frame_id(last_frame_id),
        .last_line_index(last_line_index), .last_image_id(last_image_id));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start            <= 1'b0;
            done             <= 1'b0;
            pass             <= 1'b0;
            fail             <= 1'b0;
            good_packets     <= 16'd0;
            launched_packets <= 16'd0;
            timeout_count    <= 32'd0;
        end else if (!done) begin
            start <= 1'b0;
            timeout_count <= timeout_count + 1'b1;

            if (!busy && !start && launched_packets < TEST_PACKETS) begin
                start <= 1'b1;
                launched_packets <= launched_packets + 1'b1;
            end

            if (checker_ok) begin
                good_packets <= good_packets + 1'b1;
                if (good_packets + 1'b1 >= TEST_PACKETS) begin
                    done <= 1'b1;
                    pass <= 1'b1;
                end
            end

            if (checker_error || timeout_count >= TIMEOUT_CYCLES-1) begin
                done <= 1'b1;
                fail <= 1'b1;
                pass <= 1'b0;
            end
        end
    end

    wire _unused_debug = ^sequence ^ ^expected_sequence ^ ^last_frame_id ^
                         ^last_line_index ^ ^last_image_id ^ packet_done;
endmodule
