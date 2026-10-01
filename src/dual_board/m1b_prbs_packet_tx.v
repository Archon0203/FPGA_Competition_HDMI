// ============================================================================
// M1B logical source-synchronous PRBS packet generator.
// This freezes SOF/EOF/sequence/CRC behavior independently of a final 40-pin
// physical assignment. It is a simulation/contract gate, not a claim that the
// future wide GPIO link has closed timing on hardware.
// ============================================================================
module m1b_prbs_packet_tx #(
    parameter integer WORDS_PER_PACKET = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    output wire        valid,
    output wire [31:0] data,
    output wire        sof,
    output wire        eof,
    output wire [15:0] sequence,
    output wire [15:0] packet_crc
);
    reg [31:0] lfsr;
    reg [15:0] word_index;
    reg [15:0] seq_reg;
    reg [15:0] crc_reg;

    function [31:0] prbs_next;
        input [31:0] s;
        begin
            prbs_next = {s[30:0], s[31]^s[21]^s[1]^s[0]};
        end
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

    wire [15:0] crc_after_word = crc16_word(crc_reg, lfsr);
    assign valid = enable;
    assign data = lfsr;
    assign sof = enable && (word_index == 0);
    assign eof = enable && (word_index == WORDS_PER_PACKET-1);
    assign sequence = seq_reg;
    assign packet_crc = crc_after_word;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr       <= 32'h1ACE_B00C;
            word_index <= 16'd0;
            seq_reg    <= 16'd0;
            crc_reg    <= 16'hFFFF;
        end else if (enable) begin
            lfsr <= prbs_next(lfsr);
            if (word_index == WORDS_PER_PACKET-1) begin
                word_index <= 16'd0;
                seq_reg    <= seq_reg + 1'b1;
                crc_reg    <= 16'hFFFF;
            end else begin
                word_index <= word_index + 1'b1;
                crc_reg    <= crc_after_word;
            end
        end
    end
endmodule
