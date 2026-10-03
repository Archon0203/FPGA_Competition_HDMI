// Master M2 640x480 back-buffer sink. frame_boundary must be a one-cycle
// pulse already synchronized into clk from the pixel raster.
module m2_master_frame_store #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480,
    parameter [20:0] BASE_A = 21'd0,
    parameter [20:0] BASE_B = 21'd307200
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        line_valid,
    input  wire [31:0] line_data,
    input  wire        line_start,
    input  wire        line_end,
    input  wire        frame_end,
    input  wire [15:0] line_frame_id,
    input  wire [7:0]  line_image_id,
    input  wire [15:0] line_index,
    output wire        line_ready,
    input  wire        protocol_error,
    output wire        mem_wr_valid,
    output wire [20:0] mem_wr_addr,
    output wire [31:0] mem_wr_data,
    input  wire        mem_wr_ready,
    input  wire        frame_boundary,
    output reg  [20:0] front_base,
    output reg         front_valid,
    output reg  [15:0] front_frame_id,
    output reg  [7:0]  front_image_id,
    output reg         pending_swap,
    output reg         commit_pulse,
    output reg         commit_error
);
    reg [20:0] back_base;
    reg candidate_valid;
    reg [15:0] candidate_frame, expected_line, word_index;
    reg [7:0] candidate_image;
    reg [15:0] pending_frame;
    reg [7:0] pending_image;
    wire first_word = line_start && line_index == 0;
    wire address_ok = line_index < HEIGHT && word_index < WIDTH;
    wire can_write = !pending_swap && !protocol_error && address_ok &&
                     (candidate_valid || first_word);
    wire accept = line_valid && line_ready;
    wire [31:0] pixel_offset = (line_index * WIDTH) + word_index;

    assign mem_wr_valid = line_valid && can_write;
    assign mem_wr_addr = back_base + pixel_offset[20:0];
    assign mem_wr_data = line_data;
    assign line_ready = !pending_swap && (!mem_wr_valid || mem_wr_ready);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            front_base <= BASE_A;
            back_base <= BASE_B;
            front_valid <= 0;
            front_frame_id <= 0;
            front_image_id <= 0;
            pending_swap <= 0;
            pending_frame <= 0;
            pending_image <= 0;
            candidate_valid <= 0;
            candidate_frame <= 0;
            candidate_image <= 0;
            expected_line <= 0;
            word_index <= 0;
            commit_pulse <= 0;
            commit_error <= 0;
        end else begin
            commit_pulse <= 0;
            commit_error <= 0;
            if (protocol_error) begin
                candidate_valid <= 0;
                pending_swap <= 0;
                expected_line <= 0;
                word_index <= 0;
                commit_error <= 1;
            end else begin
                if (pending_swap && frame_boundary) begin
                    front_base <= back_base;
                    back_base <= front_base;
                    front_valid <= 1;
                    front_frame_id <= pending_frame;
                    front_image_id <= pending_image;
                    pending_swap <= 0;
                    commit_pulse <= 1;
                end
                if (accept) begin
                    if (line_start) begin
                        if (word_index != 0 ||
                            (line_index != 0 &&
                             (!candidate_valid || line_index != expected_line ||
                              line_frame_id != candidate_frame ||
                              line_image_id != candidate_image))) begin
                            candidate_valid <= 0;
                            commit_error <= 1;
                        end else if (line_index == 0 &&
                                     (!candidate_valid || expected_line != 0 ||
                                      line_frame_id != candidate_frame ||
                                      line_image_id != candidate_image)) begin
                            if (candidate_valid) commit_error <= 1;
                            candidate_valid <= 1;
                            candidate_frame <= line_frame_id;
                            candidate_image <= line_image_id;
                            expected_line <= 0;
                        end
                    end else if (!candidate_valid || line_index != expected_line ||
                                 line_frame_id != candidate_frame ||
                                 line_image_id != candidate_image) begin
                        candidate_valid <= 0;
                        commit_error <= 1;
                    end

                    if (word_index == WIDTH-1) begin
                        word_index <= 0;
                        if (!line_end || !address_ok) begin
                            candidate_valid <= 0;
                            commit_error <= 1;
                        end else if (candidate_valid) begin
                            if (line_index == HEIGHT-1) begin
                                if (frame_end) begin
                                    pending_swap <= 1;
                                    pending_frame <= candidate_frame;
                                    pending_image <= candidate_image;
                                end else commit_error <= 1;
                                candidate_valid <= 0;
                            end else if (frame_end) begin
                                candidate_valid <= 0;
                                commit_error <= 1;
                            end else expected_line <= expected_line + 1'b1;
                        end
                    end else begin
                        if (line_end || frame_end) begin
                            candidate_valid <= 0;
                            word_index <= 0;
                            commit_error <= 1;
                        end else word_index <= word_index + 1'b1;
                    end
                end
            end
        end
    end
endmodule
