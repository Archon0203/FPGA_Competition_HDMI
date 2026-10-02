// M2 B/C frame-boundary commit gate.
//
// Lines are observed while a candidate frame is being received, but the
// published frame_id changes only on the final accepted line.  Any gap,
// metadata discontinuity, or upstream protocol error invalidates the
// candidate and leaves the previous front frame untouched.
module m2_frame_commit #(
    parameter integer FRAME_LINES = 480
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        line_valid,
    input  wire [31:0] line_data,
    input  wire        line_start,
    input  wire        line_end,
    input  wire        frame_end,
    input  wire [15:0] line_frame_id,
    input  wire [15:0] line_index,
    input  wire        protocol_error,

    output reg         pixel_valid,
    output reg  [31:0] pixel_data,
    output reg         frame_boundary,
    output reg         front_valid,
    output reg  [15:0] front_frame_id,
    output reg         commit_error,
    output reg  [15:0] accepted_lines
);
    reg candidate_valid;
    reg [15:0] candidate_frame;
    reg [15:0] expected_line;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            candidate_valid <= 1'b0;
            candidate_frame <= 0;
            expected_line <= 0;
            pixel_valid <= 1'b0;
            pixel_data <= 0;
            frame_boundary <= 1'b0;
            front_valid <= 1'b0;
            front_frame_id <= 0;
            commit_error <= 1'b0;
            accepted_lines <= 0;
        end else begin
            pixel_valid <= 1'b0;
            frame_boundary <= 1'b0;
            commit_error <= 1'b0;

            if (protocol_error) begin
                candidate_valid <= 1'b0;
                expected_line <= 0;
                commit_error <= 1'b1;
            end

            if (line_valid) begin
                pixel_valid <= 1'b1;
                pixel_data <= line_data;
                if (line_start) begin
                    if (!candidate_valid) begin
                        candidate_valid <= 1'b1;
                        candidate_frame <= line_frame_id;
                        expected_line <= line_index;
                        accepted_lines <= 0;
                    end else if (line_frame_id != candidate_frame || line_index != expected_line) begin
                        candidate_valid <= 1'b0;
                        commit_error <= 1'b1;
                    end
                end
                if (line_end && candidate_valid) begin
                    if (line_index != expected_line) begin
                        candidate_valid <= 1'b0;
                        commit_error <= 1'b1;
                    end else begin
                        accepted_lines <= accepted_lines + 1'b1;
                        expected_line <= expected_line + 1'b1;
                        if (frame_end && (line_index == FRAME_LINES-1)) begin
                            front_valid <= 1'b1;
                            front_frame_id <= candidate_frame;
                            frame_boundary <= 1'b1;
                            candidate_valid <= 1'b0;
                        end
                    end
                end
            end
        end
    end
endmodule
