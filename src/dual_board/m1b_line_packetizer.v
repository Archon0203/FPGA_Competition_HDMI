// ============================================================================
// M1 B-line line-packet contract formatter (transport-independent word stream).
// Packet words:
//   W0  0x4D314C31  ("M1L1")
//   W1  {frame_id[15:0], line_index[15:0]}
//   W2  {image_id[7:0], sequence[7:0], payload_words[15:0]}
//   W3.. payload words
//   LAST {16'hC16C, crc16_ccitt}
// CRC covers W0..last payload word, MSB byte first, init FFFF, poly 1021.
// ============================================================================
module m1b_line_packetizer #(
    parameter integer PAYLOAD_WORDS = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [15:0] frame_id,
    input  wire [7:0]  image_id,
    input  wire [15:0] line_index,

    input  wire        in_valid,
    input  wire [31:0] in_data,
    output wire        in_ready,

    output reg         out_valid,
    output reg  [31:0] out_data,
    output reg         out_last,
    input  wire        out_ready,

    output wire        busy,
    output reg         packet_done,
    output reg  [7:0]  sequence
);
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_H0   = 3'd1;
    localparam [2:0] ST_H1   = 3'd2;
    localparam [2:0] ST_H2   = 3'd3;
    localparam [2:0] ST_PAY  = 3'd4;
    localparam [2:0] ST_CRC  = 3'd5;
    localparam [15:0] PAYLOAD_WORDS_U16 = PAYLOAD_WORDS;

    reg [2:0] state;
    reg [15:0] frame_latched;
    reg [7:0]  image_latched;
    reg [15:0] line_latched;
    reg [15:0] payload_count;
    reg [15:0] crc;

    function [15:0] crc16_byte;
        input [15:0] crc_in;
        input [7:0] data;
        integer i;
        reg [15:0] c;
        begin
            c = crc_in ^ ({data, 8'h00});
            for (i = 0; i < 8; i = i + 1)
                c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
            crc16_byte = c;
        end
    endfunction

    function [15:0] crc16_word;
        input [15:0] crc_in;
        input [31:0] data;
        reg [15:0] c;
        begin
            c = crc16_byte(crc_in, data[31:24]);
            c = crc16_byte(c, data[23:16]);
            c = crc16_byte(c, data[15:8]);
            c = crc16_byte(c, data[7:0]);
            crc16_word = c;
        end
    endfunction

    assign busy = (state != ST_IDLE);
    assign in_ready = (state == ST_PAY) && out_ready;

    always @(*) begin
        out_valid = 1'b0;
        out_data  = 32'd0;
        out_last  = 1'b0;
        case (state)
            ST_H0: begin out_valid = 1'b1; out_data = 32'h4D314C31; end
            ST_H1: begin out_valid = 1'b1; out_data = {frame_latched, line_latched}; end
            ST_H2: begin out_valid = 1'b1; out_data = {image_latched, sequence, PAYLOAD_WORDS_U16}; end
            ST_PAY: begin out_valid = in_valid; out_data = in_data; end
            ST_CRC: begin out_valid = 1'b1; out_data = {16'hC16C, crc}; out_last = 1'b1; end
            default: ;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            frame_latched  <= 16'd0;
            image_latched  <= 8'd0;
            line_latched   <= 16'd0;
            payload_count  <= 16'd0;
            crc            <= 16'hFFFF;
            packet_done    <= 1'b0;
            sequence       <= 8'd0;
        end else begin
            packet_done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        frame_latched <= frame_id;
                        image_latched <= image_id;
                        line_latched  <= line_index;
                        payload_count <= 16'd0;
                        crc           <= 16'hFFFF;
                        state         <= ST_H0;
                    end
                end
                ST_H0: if (out_ready) begin
                    crc   <= crc16_word(crc, 32'h4D314C31);
                    state <= ST_H1;
                end
                ST_H1: if (out_ready) begin
                    crc   <= crc16_word(crc, {frame_latched, line_latched});
                    state <= ST_H2;
                end
                ST_H2: if (out_ready) begin
                    crc <= crc16_word(crc, {image_latched, sequence, PAYLOAD_WORDS_U16});
                    state <= (PAYLOAD_WORDS == 0) ? ST_CRC : ST_PAY;
                end
                ST_PAY: if (in_valid && out_ready) begin
                    crc <= crc16_word(crc, in_data);
                    if (payload_count + 1'b1 >= PAYLOAD_WORDS_U16) begin
                        payload_count <= 16'd0;
                        state <= ST_CRC;
                    end else begin
                        payload_count <= payload_count + 1'b1;
                    end
                end
                ST_CRC: if (out_ready) begin
                    sequence    <= sequence + 1'b1;
                    packet_done <= 1'b1;
                    state       <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
