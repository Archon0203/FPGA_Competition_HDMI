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

    output reg         line_valid,
    output reg  [31:0] line_data,
    input  wire        line_ready,
    output reg         line_start,
    output reg         line_end,
    output reg         frame_end,
    output reg  [15:0] frame_id,
    output reg  [15:0] line_index,
    output reg  [7:0]  image_id,
    output reg         frame_accept,
    output reg         protocol_error,
    output reg         link_ready,
    output reg  [7:0]  expected_sequence
);
    localparam [2:0] ST_MAGIC=0, ST_META1=1, ST_META2=2, ST_PAY=3,
                     ST_CRC=4, ST_EMIT=5;
    reg [2:0] state;
    reg [15:0] crc;
    reg [15:0] payload_words;
    reg [15:0] payload_count;
    reg [15:0] emit_count;
    reg header_error;
    reg [15:0] frame_q, line_q;
    reg [7:0] image_q;
    // M2 first specification is four words/line.  Keeping the four entries
    // explicit avoids an unintended vendor RAM inference in the small local
    // diagnostic; the same interface can be widened to a BRAM-backed line
    // store for the M3 tile profile.
    reg [31:0] line_mem0, line_mem1, line_mem2, line_mem3;
    reg [31:0] emit_word;

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_MAGIC;
            crc <= 16'hffff;
            payload_words <= 0;
            payload_count <= 0;
            emit_count <= 0;
            header_error <= 1'b0;
            frame_q <= 0; line_q <= 0; image_q <= 0;
            line_mem0 <= 0; line_mem1 <= 0; line_mem2 <= 0; line_mem3 <= 0;
            emit_word <= 0;
            line_valid <= 1'b0; line_data <= 0;
            line_start <= 1'b0; line_end <= 1'b0; frame_end <= 1'b0;
            frame_id <= 0; line_index <= 0; image_id <= 0;
            frame_accept <= 1'b0; protocol_error <= 1'b0;
            link_ready <= 1'b0; expected_sequence <= 0;
        end else begin
            line_valid <= 1'b0;
            line_start <= 1'b0;
            line_end <= 1'b0;
            frame_end <= 1'b0;
            frame_accept <= 1'b0;
            protocol_error <= 1'b0;

            if (state == ST_EMIT) begin
                line_valid <= 1'b1;
                case (emit_count)
                    0: emit_word = line_mem0;
                    1: emit_word = line_mem1;
                    2: emit_word = line_mem2;
                    default: emit_word = line_mem3;
                endcase
                line_data <= emit_word;
                line_start <= (emit_count == 0);
                line_end <= (emit_count + 1'b1 >= payload_words);
                frame_end <= ((emit_count + 1'b1 >= payload_words) &&
                              (line_q == FRAME_LINES-1));
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
                        payload_count <= 0;
                        state <= ST_META1;
                    end
                    ST_META1: begin
                        frame_q <= in_data[31:16];
                        line_q <= in_data[15:0];
                        crc <= crc16_word(crc,in_data);
                        state <= ST_META2;
                    end
                    ST_META2: begin
                        image_q <= in_data[31:24];
                        payload_words <= in_data[15:0];
                        if (in_data[23:16] != expected_sequence ||
                            in_data[15:0] == 0 || in_data[15:0] > LINE_WORDS)
                            header_error <= 1'b1;
                        crc <= crc16_word(crc,in_data);
                        state <= (in_data[15:0] == 0 || in_data[15:0] > LINE_WORDS) ? ST_CRC : ST_PAY;
                    end
                    ST_PAY: begin
                        case (payload_count)
                            0: line_mem0 <= in_data;
                            1: line_mem1 <= in_data;
                            2: line_mem2 <= in_data;
                            default: line_mem3 <= in_data;
                        endcase
                        crc <= crc16_word(crc,in_data);
                        if (payload_count + 1'b1 >= payload_words) begin
                            payload_count <= 0;
                            state <= ST_CRC;
                        end else payload_count <= payload_count + 1'b1;
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
