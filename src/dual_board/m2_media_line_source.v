// ============================================================================
// M2 A-line media source contract.
//
// This module is the transport-facing side of the Slave media service.  The
// storage provider (TF/FAT32/BMP) supplies a selected image and descriptor in
// the same command/status shape; the default implementation below is a small
// synthesizable BMP-compatible line source used for M2 bring-up and rollback.
// It deliberately exposes line/credit boundaries so the real BMP pixel stream
// can replace only this producer in a later revision.
//
// One output word is 0x00RRGGBB for the first specification.  A line is
// packetized only after a credit is consumed.  No line is dropped when
// downstream backpressure is asserted.
// ============================================================================
module m2_media_line_source #(
    parameter integer IMAGE_WIDTH      = 640,
    parameter integer IMAGE_HEIGHT     = 480,
    parameter integer WORDS_PER_LINE   = 4,
    parameter integer CATALOG_COUNT    = 4,
    parameter integer CREDIT_MAX       = 16'hffff
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire [7:0]  cmd_image_id,
    input  wire        cmd_play,
    input  wire        cmd_pause,
    input  wire [15:0] credit_add,

    output reg         catalog_valid,
    output reg  [7:0]  catalog_count,
    output reg  [15:0] catalog_epoch,
    output reg         descriptor_valid,
    output reg  [7:0]  descriptor_image_id,
    output reg  [15:0] descriptor_width,
    output reg  [15:0] descriptor_height,
    output reg         source_ready,
    output reg         source_busy,
    output reg         source_done,
    output reg         source_error,
    output reg  [15:0] credit_level,

    output wire        packet_start,
    output wire [15:0] frame_id,
    output wire [7:0]  image_id,
    output wire [15:0] line_index,
    output wire        line_start,
    output wire        line_end,
    output wire        frame_end,
    output wire        data_valid,
    input  wire        data_ready,
    output wire [31:0] data_word
);
    localparam [1:0] ST_IDLE = 2'd0, ST_WAIT = 2'd1, ST_STREAM = 2'd2;
    reg [1:0] state;
    reg [7:0] selected_image;
    reg [15:0] frame_q, line_q, word_q;
    reg playing_q;
    reg packet_start_q;

    assign cmd_ready = (state != ST_STREAM);
    assign packet_start = packet_start_q;
    assign frame_id = frame_q;
    assign image_id = selected_image;
    assign line_index = line_q;
    assign line_start = (state == ST_STREAM) && (word_q == 0);
    assign line_end = (state == ST_STREAM) && (word_q == WORDS_PER_LINE-1);
    assign frame_end = line_end && (line_q == IMAGE_HEIGHT-1);
    assign data_valid = (state == ST_STREAM);
    assign data_word = {8'h00, selected_image ^ line_q[7:0],
                        word_q[7:0], selected_image + line_q[7:0] + word_q[7:0]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            selected_image <= 0;
            frame_q <= 0;
            line_q <= 0;
            word_q <= 0;
            playing_q <= 1'b0;
            packet_start_q <= 1'b0;
            catalog_valid <= 1'b0;
            catalog_count <= 0;
            catalog_epoch <= 0;
            descriptor_valid <= 1'b0;
            descriptor_image_id <= 0;
            descriptor_width <= 0;
            descriptor_height <= 0;
            source_ready <= 1'b0;
            source_busy <= 1'b0;
            source_done <= 1'b0;
            source_error <= 1'b0;
            credit_level <= 0;
        end else begin
            packet_start_q <= 1'b0;
            descriptor_valid <= 1'b0;
            source_done <= 1'b0;
            source_error <= 1'b0;
            catalog_valid <= 1'b1;
            catalog_count <= CATALOG_COUNT[7:0];
            catalog_epoch <= 16'd1;

            if (credit_add != 0) begin
                if (credit_level + credit_add < credit_level ||
                    credit_level + credit_add > CREDIT_MAX)
                    credit_level <= CREDIT_MAX;
                else
                    credit_level <= credit_level + credit_add;
            end

            if (cmd_valid && cmd_ready) begin
                if (cmd_image_id < CATALOG_COUNT) begin
                    selected_image <= cmd_image_id;
                    frame_q <= frame_q + 1'b1;
                    line_q <= 0;
                    word_q <= 0;
                    source_ready <= 1'b1;
                    descriptor_valid <= 1'b1;
                    descriptor_image_id <= cmd_image_id;
                    descriptor_width <= IMAGE_WIDTH;
                    descriptor_height <= IMAGE_HEIGHT;
                    if (cmd_play) playing_q <= 1'b1;
                    if (cmd_pause) playing_q <= 1'b0;
                    state <= (cmd_play && (credit_level != 0)) ? ST_STREAM : ST_WAIT;
                end else begin
                    source_error <= 1'b1;
                end
            end

            if (state == ST_WAIT && playing_q && source_ready && credit_level != 0) begin
                credit_level <= credit_level - 1'b1;
                packet_start_q <= 1'b1;
                word_q <= 0;
                state <= ST_STREAM;
            end else if (state == ST_STREAM && data_valid && data_ready) begin
                if (word_q == WORDS_PER_LINE-1) begin
                    word_q <= 0;
                    if (line_q == IMAGE_HEIGHT-1) begin
                        line_q <= 0;
                        frame_q <= frame_q + 1'b1;
                        source_done <= 1'b1;
                        state <= ST_WAIT;
                    end else begin
                        line_q <= line_q + 1'b1;
                        state <= ST_WAIT;
                    end
                end else begin
                    word_q <= word_q + 1'b1;
                end
            end
            source_busy <= (state != ST_IDLE) && (playing_q || (state == ST_STREAM));
        end
    end
endmodule
