// ============================================================================
// M2 B-line packet receiver.
//
// CRC and sequence are checked before any payload is released.  Consequently
// a truncated/corrupted packet can never write a partial line into the display
// side.  The small line RAM is intentionally parameterized; M2 uses four
// words/line for the contract regression and M3 can raise it to the selected
// packed-YUV line or tile size.
// ============================================================================
module m2_line_packet_rx #(
    parameter integer LINE_WORDS  = 4,
    parameter integer FRAME_LINES = 480
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_data,
    input  wire        in_last,
    output wire        in_ready,

    output wire        line_valid,
    output wire [31:0] line_data,
    input  wire        line_ready,
    output wire        line_start,
    output wire        line_end,
    output wire        frame_end,
    output reg  [15:0] frame_id,
    output reg  [15:0] line_index,
    output reg  [7:0]  image_id,
    output reg         frame_accept,
    output reg         protocol_error,
    output reg         link_ready,
    output reg  [7:0]  expected_sequence
);
    localparam [2:0] ST_MAGIC=0, ST_META1=1, ST_META2=2, ST_PAY=3,
                     ST_CRC=4, ST_EMIT=5, ST_DROP=6;
    reg [2:0] state;
    reg [15:0] crc;
    reg [15:0] payload_words;
    reg [15:0] payload_count;
    reg [15:0] emit_count;
    reg header_error;
    reg magic_ok;
    reg [15:0] frame_q, line_q;
    reg [7:0] image_q;
    reg [7:0] sequence_q;
    reg [31:0] line_mem [0:LINE_WORDS-1];

    function [15:0] crc16_byte;
        input [15:0] crc_in; input [7:0] data;
        integer i; reg [15:0] c;
        begin
            c = crc_in ^ {data,8'h00};
            for (i=0;i<8;i=i+1) c = c[15] ? ((c<<1)^16'h1021) : (c<<1);
            crc16_byte = c;
        end
    endfunction
    function [15:0] crc16_word;
        input [15:0] crc_in; input [31:0] data;
        reg [15:0] c;
        begin
            c=crc16_byte(crc_in,data[31:24]); c=crc16_byte(c,data[23:16]);
            c=crc16_byte(c,data[15:8]); c=crc16_byte(c,data[7:0]);
            crc16_word=c;
        end
    endfunction

    assign in_ready = (state != ST_EMIT);
    assign line_valid = (state == ST_EMIT);
    assign line_data = line_mem[emit_count];
    assign line_start = line_valid && (emit_count == 0);
    assign line_end = line_valid && (emit_count + 1'b1 == payload_words);
    assign frame_end = line_end && (line_q == FRAME_LINES-1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_MAGIC;
            crc <= 16'hffff;
            payload_words <= 0;
            payload_count <= 0;
            emit_count <= 0;
            header_error <= 1'b0;
            magic_ok <= 1'b0;
            frame_q <= 0; line_q <= 0; image_q <= 0;
            sequence_q <= 0;
            frame_id <= 0; line_index <= 0; image_id <= 0;
            frame_accept <= 1'b0; protocol_error <= 1'b0;
            link_ready <= 1'b0; expected_sequence <= 0;
        end else begin
            frame_accept <= 1'b0;
            protocol_error <= 1'b0;

            if (state == ST_EMIT) begin
                if (line_ready) begin
                    if (emit_count + 1'b1 >= payload_words) begin
                        frame_accept <= (line_q == FRAME_LINES-1);
                        state <= ST_MAGIC;
                        crc <= 16'hffff;
                    end else begin
                        emit_count <= emit_count + 1'b1;
                    end
                end
            end else if (in_valid && in_ready) begin
                case (state)
                    ST_MAGIC: begin
                        crc <= crc16_word(16'hffff,in_data);
                        header_error <= (in_data != 32'h4d314c31);
                        magic_ok <= (in_data == 32'h4d314c31);
                        payload_count <= 0;
                        state <= in_last ? ST_MAGIC : ST_META1;
                        if (in_last) protocol_error <= 1'b1;
                    end
                    ST_META1: begin
                        frame_q <= in_data[31:16];
                        line_q <= in_data[15:0];
                        crc <= crc16_word(crc,in_data);
                        state <= in_last ? ST_MAGIC : ST_META2;
                        if (in_last) protocol_error <= 1'b1;
                    end
                    ST_META2: begin
                        image_q <= in_data[31:24];
                        sequence_q <= in_data[23:16];
                        payload_words <= in_data[15:0];
                        if (in_data[23:16] != expected_sequence ||
                            in_data[15:0] != LINE_WORDS)
                            header_error <= 1'b1;
                        crc <= crc16_word(crc,in_data);
                        state <= in_last ? ST_MAGIC :
                                 (in_data[15:0] != LINE_WORDS) ? ST_DROP : ST_PAY;
                        if (in_last || in_data[15:0] != LINE_WORDS)
                            protocol_error <= 1'b1;
                    end
                    ST_DROP: if (in_last) begin
                        expected_sequence <= sequence_q + 1'b1;
                        state <= ST_MAGIC;
                        crc <= 16'hffff;
                    end
                    ST_PAY: begin
                        if (in_last) begin
                            protocol_error <= 1'b1;
                            expected_sequence <= sequence_q + 1'b1;
                            state <= ST_MAGIC;
                        end else begin
                            line_mem[payload_count] <= in_data;
                            crc <= crc16_word(crc,in_data);
                        end
                        if (!in_last && payload_count + 1'b1 >= payload_words) begin
                            payload_count <= 0;
                            state <= ST_CRC;
                        end else if (!in_last) payload_count <= payload_count + 1'b1;
                    end
                    ST_CRC: begin
                        if (!header_error && in_last && in_data[31:16] == 16'hc16c && in_data[15:0] == crc) begin
                            frame_id <= frame_q; line_index <= line_q; image_id <= image_q;
                            emit_count <= 0;
                            link_ready <= 1'b1;
                            expected_sequence <= expected_sequence + 1'b1;
                            state <= ST_EMIT;
                        end else begin
                            protocol_error <= 1'b1;
                            if (in_last && in_data[31:16] == 16'hc16c &&
                                magic_ok && payload_words == LINE_WORDS)
                                expected_sequence <= sequence_q + 1'b1;
                            state <= ST_MAGIC;
                            crc <= 16'hffff;
                        end
                    end
                    default: state <= ST_MAGIC;
                endcase
            end
        end
    end
endmodule
