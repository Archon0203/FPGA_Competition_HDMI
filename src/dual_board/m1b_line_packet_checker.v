// M1 B-line checker matching m1b_line_packetizer.
module m1b_line_packet_checker (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_data,
    input  wire        in_last,
    output wire        in_ready,
    output reg         packet_ok,
    output reg         packet_error,
    output reg  [7:0]  expected_sequence,
    output reg  [15:0] last_frame_id,
    output reg  [15:0] last_line_index,
    output reg  [7:0]  last_image_id
);
    localparam [2:0] ST_MAGIC = 3'd0;
    localparam [2:0] ST_META1 = 3'd1;
    localparam [2:0] ST_META2 = 3'd2;
    localparam [2:0] ST_PAY   = 3'd3;
    localparam [2:0] ST_CRC   = 3'd4;

    reg [2:0]  state;
    reg [15:0] crc;
    reg [15:0] payload_words;
    reg [15:0] payload_count;
    reg        header_error;

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

    assign in_ready = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= ST_MAGIC;
            crc               <= 16'hFFFF;
            payload_words     <= 16'd0;
            payload_count     <= 16'd0;
            header_error      <= 1'b0;
            packet_ok         <= 1'b0;
            packet_error      <= 1'b0;
            expected_sequence <= 8'd0;
            last_frame_id     <= 16'd0;
            last_line_index   <= 16'd0;
            last_image_id     <= 8'd0;
        end else begin
            packet_ok    <= 1'b0;
            packet_error <= 1'b0;

            if (in_valid) begin
                case (state)
                    ST_MAGIC: begin
                        crc           <= crc16_word(16'hFFFF, in_data);
                        payload_count <= 16'd0;
                        header_error  <= (in_data != 32'h4D314C31);
                        state         <= ST_META1;
                    end
                    ST_META1: begin
                        last_frame_id   <= in_data[31:16];
                        last_line_index <= in_data[15:0];
                        crc             <= crc16_word(crc, in_data);
                        state           <= ST_META2;
                    end
                    ST_META2: begin
                        last_image_id <= in_data[31:24];
                        payload_words <= in_data[15:0];
                        if (in_data[23:16] != expected_sequence)
                            header_error <= 1'b1;
                        crc <= crc16_word(crc, in_data);
                        state <= (in_data[15:0] == 0) ? ST_CRC : ST_PAY;
                    end
                    ST_PAY: begin
                        crc <= crc16_word(crc, in_data);
                        if (payload_count + 1'b1 >= payload_words) begin
                            payload_count <= 16'd0;
                            state <= ST_CRC;
                        end else begin
                            payload_count <= payload_count + 1'b1;
                        end
                    end
                    ST_CRC: begin
                        if (!header_error && in_last && in_data[31:16] == 16'hC16C && in_data[15:0] == crc) begin
                            packet_ok <= 1'b1;
                            expected_sequence <= expected_sequence + 1'b1;
                        end else begin
                            packet_error <= 1'b1;
                        end
                        state <= ST_MAGIC;
                        crc   <= 16'hFFFF;
                    end
                    default: state <= ST_MAGIC;
                endcase
            end
        end
    end
endmodule
