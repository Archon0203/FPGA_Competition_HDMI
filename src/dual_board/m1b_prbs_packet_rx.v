// ============================================================================
// M1B checker for m1b_prbs_packet_tx.
// ============================================================================
module m1b_prbs_packet_rx #(
    parameter integer WORDS_PER_PACKET = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid,
    input  wire [31:0] data,
    input  wire        sof,
    input  wire        eof,
    input  wire [15:0] sequence,
    input  wire [15:0] packet_crc,
    output reg  [31:0] word_count,
    output reg  [31:0] packet_count,
    output reg  [31:0] data_errors,
    output reg  [31:0] sequence_errors,
    output reg  [31:0] crc_errors,
    output reg         locked
);
    reg [31:0] expected_lfsr;
    reg [15:0] word_index;
    reg [15:0] expected_seq;
    reg [15:0] crc_reg;

    function [31:0] prbs_next;
        input [31:0] s;
        begin prbs_next = {s[30:0], s[31]^s[21]^s[1]^s[0]}; end
    endfunction

    function [15:0] crc16_byte;
        input [15:0] crc_in;
        input [7:0] d;
        integer i;
        reg [15:0] c;
        begin
            c = crc_in ^ {d,8'h00};
            for (i=0;i<8;i=i+1)
                c = c[15] ? ({c[14:0],1'b0} ^ 16'h1021) : {c[14:0],1'b0};
            crc16_byte = c;
        end
    endfunction

    function [15:0] crc16_word;
        input [15:0] crc_in;
        input [31:0] w;
        reg [15:0] c;
        begin
            c = crc_in;
            c = crc16_byte(c,w[31:24]);
            c = crc16_byte(c,w[23:16]);
            c = crc16_byte(c,w[15:8]);
            c = crc16_byte(c,w[7:0]);
            crc16_word = c;
        end
    endfunction

    wire [15:0] crc_after_word = crc16_word(crc_reg, data);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            expected_lfsr  <= 32'h1ACE_B00C;
            word_index     <= 16'd0;
            expected_seq   <= 16'd0;
            crc_reg        <= 16'hFFFF;
            word_count     <= 32'd0;
            packet_count   <= 32'd0;
            data_errors    <= 32'd0;
            sequence_errors<= 32'd0;
            crc_errors     <= 32'd0;
            locked         <= 1'b0;
        end else if (valid) begin
            word_count <= word_count + 1'b1;
            if (data != expected_lfsr)
                data_errors <= data_errors + 1'b1;
            expected_lfsr <= prbs_next(expected_lfsr);

            if (sof) begin
                locked <= 1'b1;
                if (word_index != 0 || sequence != expected_seq)
                    sequence_errors <= sequence_errors + 1'b1;
            end

            if (eof) begin
                packet_count <= packet_count + 1'b1;
                if (word_index != WORDS_PER_PACKET-1)
                    sequence_errors <= sequence_errors + 1'b1;
                if (packet_crc != crc_after_word)
                    crc_errors <= crc_errors + 1'b1;
                word_index   <= 16'd0;
                expected_seq <= expected_seq + 1'b1;
                crc_reg      <= 16'hFFFF;
            end else begin
                word_index <= word_index + 1'b1;
                crc_reg    <= crc_after_word;
            end
        end
    end
endmodule
