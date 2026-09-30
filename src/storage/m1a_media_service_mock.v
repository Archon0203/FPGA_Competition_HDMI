`include "m1a_protocol.vh"

// M1A from-board media-service shell.
// The catalog and packet source are deterministic mocks so the control and
// credit contracts can be verified before the physical TF provider exists.
module m1a_media_service_mock #(
    parameter integer IMAGE_WIDTH  = 640,
    parameter integer IMAGE_HEIGHT = 480,
    parameter integer MOCK_LINES   = IMAGE_HEIGHT,
    parameter integer WORDS_PER_LINE = 4,
    parameter integer CATALOG_COUNT = 4,
    parameter integer CREDIT_MAX = 16'hffff
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cmd_valid,
    input  wire [7:0]  cmd_opcode,
    input  wire [31:0] cmd_arg,
    output wire        cmd_ready,

    output reg         catalog_valid,
    output reg  [7:0]  catalog_count,
    output reg  [15:0] catalog_epoch,
    output reg         descriptor_valid,
    output reg  [7:0]  descriptor_image_id,
    output reg  [1:0]  descriptor_type,
    output reg  [15:0] descriptor_width,
    output reg  [15:0] descriptor_height,
    output reg  [15:0] descriptor_frame_count,
    output reg  [31:0] descriptor_duration,

    output reg         status_valid,
    output reg  [7:0]  status_code,
    output reg  [7:0]  status_error,
    output wire        source_ready,
    output wire        source_busy,
    output reg         source_done,
    output reg         source_error,
    output reg  [15:0] credit_level,

    output wire        media_valid,
    input  wire        media_ready,
    output wire [31:0] media_data,
    output wire        media_line_start,
    output wire        media_line_end,
    output wire        media_frame_end,
    output wire [15:0] media_frame_id,
    output wire  [7:0] media_image_id,
    output wire [15:0] media_line_index
);
    reg selected_valid;
    reg [7:0] selected_image;
    reg [3:0] selected_format;
    reg playing;
    reg packet_active;
    reg [15:0] line_index;
    reg [15:0] word_index;
    reg [15:0] frame_id;

    wire last_word = (word_index == WORDS_PER_LINE-1);
    wire last_line = (line_index == MOCK_LINES-1);
    wire [31:0] pattern_word = {
        selected_image,
        line_index[7:0],
        word_index[7:0],
        selected_image ^ line_index[7:0] ^ word_index[7:0]
    };
    assign cmd_ready = ~packet_active;
    assign source_ready = selected_valid;
    assign source_busy = packet_active | (playing & selected_valid);
    assign media_valid = packet_active;
    assign media_data = pattern_word;
    assign media_line_start = packet_active && (word_index == 0);
    assign media_line_end = packet_active && last_word;
    assign media_frame_end = packet_active && last_word && last_line;
    assign media_frame_id = frame_id;
    assign media_image_id = selected_image;
    assign media_line_index = line_index;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            catalog_valid <= 1'b0;
            catalog_count <= 8'd0;
            catalog_epoch <= 16'd0;
            descriptor_valid <= 1'b0;
            descriptor_image_id <= 8'd0;
            descriptor_type <= 2'd0;
            descriptor_width <= 16'd0;
            descriptor_height <= 16'd0;
            descriptor_frame_count <= 16'd0;
            descriptor_duration <= 32'd0;
            status_valid <= 1'b0;
            status_code <= 8'd0;
            status_error <= 8'd0;
            selected_valid <= 1'b0;
            selected_image <= 8'd0;
            selected_format <= `M1A_FORMAT_RGB888;
            playing <= 1'b0;
            packet_active <= 1'b0;
            line_index <= 16'd0;
            word_index <= 16'd0;
            frame_id <= 16'd0;
            source_done <= 1'b0;
            source_error <= 1'b0;
            credit_level <= 16'd0;
        end else begin
            catalog_valid <= 1'b1;
            catalog_count <= CATALOG_COUNT[7:0];
            catalog_epoch <= 16'd1;
            descriptor_valid <= 1'b0;
            status_valid <= 1'b0;
            source_done <= 1'b0;
            source_error <= 1'b0;

            // A credit authorizes exactly one line packet. Saturation avoids wrap.
            if (cmd_valid && cmd_ready) begin
                case (cmd_opcode)
                    `M1A_CMD_OPEN: begin
                        if (cmd_arg[7:0] < CATALOG_COUNT) begin
                            selected_valid <= 1'b1;
                            selected_image <= cmd_arg[7:0];
                            playing <= 1'b0;
                            packet_active <= 1'b0;
                            line_index <= 16'd0;
                            word_index <= 16'd0;
                            descriptor_valid <= 1'b1;
                            descriptor_image_id <= cmd_arg[7:0];
                            descriptor_type <= `M1A_MEDIA_BMP;
                            descriptor_width <= IMAGE_WIDTH;
                            descriptor_height <= IMAGE_HEIGHT;
                            descriptor_frame_count <= 16'd1;
                            descriptor_duration <= 32'd1_000_000;
                            status_valid <= 1'b1;
                            status_code <= `M1A_STATUS_READY;
                            status_error <= 8'd0;
                        end else begin
                            status_valid <= 1'b1;
                            status_code <= `M1A_STATUS_ERROR;
                            status_error <= `M1A_ERR_BAD_IMAGE;
                        end
                    end
                    `M1A_CMD_NEXT: begin
                        if (!selected_valid) begin
                            status_valid <= 1'b1;
                            status_code <= `M1A_STATUS_ERROR;
                            status_error <= `M1A_ERR_NOT_READY;
                        end else begin
                            selected_image <= (selected_image + 1'b1 >= CATALOG_COUNT) ? 0 : selected_image + 1'b1;
                            descriptor_valid <= 1'b1;
                            descriptor_image_id <= (selected_image + 1'b1 >= CATALOG_COUNT) ? 0 : selected_image + 1'b1;
                            descriptor_type <= `M1A_MEDIA_BMP;
                            descriptor_width <= IMAGE_WIDTH;
                            descriptor_height <= IMAGE_HEIGHT;
                            descriptor_frame_count <= 16'd1;
                            descriptor_duration <= 32'd1_000_000;
                            status_valid <= 1'b1;
                            status_code <= `M1A_STATUS_READY;
                            status_error <= 8'd0;
                        end
                    end
                    `M1A_CMD_PREV: begin
                        if (!selected_valid) begin
                            status_valid <= 1'b1;
                            status_code <= `M1A_STATUS_ERROR;
                            status_error <= `M1A_ERR_NOT_READY;
                        end else begin
                            selected_image <= (selected_image == 0) ? CATALOG_COUNT-1 : selected_image - 1'b1;
                            descriptor_valid <= 1'b1;
                            descriptor_image_id <= (selected_image == 0) ? CATALOG_COUNT-1 : selected_image - 1'b1;
                            descriptor_type <= `M1A_MEDIA_BMP;
                            descriptor_width <= IMAGE_WIDTH;
                            descriptor_height <= IMAGE_HEIGHT;
                            descriptor_frame_count <= 16'd1;
                            descriptor_duration <= 32'd1_000_000;
                            status_valid <= 1'b1;
                            status_code <= `M1A_STATUS_READY;
                            status_error <= 8'd0;
                        end
                    end
                    `M1A_CMD_PLAY: begin
                        if (selected_valid) begin
                            playing <= 1'b1;
                            status_valid <= 1'b1;
                            status_code <= `M1A_STATUS_ACCEPTED;
                            status_error <= 8'd0;
                        end else begin
                            status_valid <= 1'b1;
                            status_code <= `M1A_STATUS_ERROR;
                            status_error <= `M1A_ERR_NOT_READY;
                        end
                    end
                    `M1A_CMD_PAUSE: begin
                        playing <= 1'b0;
                        status_valid <= 1'b1;
                        status_code <= `M1A_STATUS_ACCEPTED;
                        status_error <= 8'd0;
                    end
                    `M1A_CMD_SET_FORMAT: begin
                        selected_format <= cmd_arg[3:0];
                        status_valid <= 1'b1;
                        status_code <= `M1A_STATUS_ACCEPTED;
                        status_error <= 8'd0;
                    end
                    `M1A_CMD_CREDIT: begin
                        if (credit_level + cmd_arg[15:0] < credit_level ||
                            credit_level + cmd_arg[15:0] > CREDIT_MAX)
                            credit_level <= CREDIT_MAX;
                        else
                            credit_level <= credit_level + cmd_arg[15:0];
                        status_valid <= 1'b1;
                        status_code <= `M1A_STATUS_CREDIT;
                        status_error <= 8'd0;
                    end
                    `M1A_CMD_ABORT: begin
                        playing <= 1'b0;
                        packet_active <= 1'b0;
                        credit_level <= 16'd0;
                        status_valid <= 1'b1;
                        status_code <= `M1A_STATUS_ACCEPTED;
                        status_error <= 8'd0;
                    end
                    `M1A_CMD_STATUS: begin
                        status_valid <= 1'b1;
                        status_code <= selected_valid ? `M1A_STATUS_READY : `M1A_STATUS_ERROR;
                        status_error <= selected_valid ? 8'd0 : `M1A_ERR_NOT_READY;
                    end
                    default: begin
                        status_valid <= 1'b1;
                        status_code <= `M1A_STATUS_ERROR;
                        status_error <= `M1A_ERR_BAD_FRAME;
                    end
                endcase
            end

            // Start only at a packet boundary after credit and PLAY are present.
            if (!packet_active && playing && selected_valid && (credit_level != 0) &&
                !(cmd_valid && (cmd_opcode == `M1A_CMD_CREDIT))) begin
                packet_active <= 1'b1;
                word_index <= 16'd0;
                credit_level <= credit_level - 1'b1;
            end else if (packet_active && media_ready) begin
                if (last_word) begin
                    packet_active <= 1'b0;
                    if (last_line) begin
                        line_index <= 16'd0;
                        frame_id <= frame_id + 1'b1;
                        source_done <= 1'b1;
                    end else begin
                        line_index <= line_index + 1'b1;
                    end
                    word_index <= 16'd0;
                end else begin
                    word_index <= word_index + 1'b1;
                end
            end
        end
    end
endmodule
