`timescale 1ns/1ps
module tb_m1b_prbs_link;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg enable = 1'b0;
    wire valid, sof, eof;
    wire [31:0] data;
    wire [15:0] sequence, packet_crc;
    wire [31:0] word_count, packet_count, data_errors, sequence_errors, crc_errors;
    wire locked;

    always #6.734 clk = ~clk; // ~74.25 MHz logical data-link clock

    m1b_prbs_packet_tx #(.WORDS_PER_PACKET(16)) u_tx (
        .clk(clk), .rst_n(rst_n), .enable(enable), .valid(valid), .data(data),
        .sof(sof), .eof(eof), .sequence(sequence), .packet_crc(packet_crc));
    m1b_prbs_packet_rx #(.WORDS_PER_PACKET(16)) u_rx (
        .clk(clk), .rst_n(rst_n), .valid(valid), .data(data), .sof(sof), .eof(eof),
        .sequence(sequence), .packet_crc(packet_crc), .word_count(word_count),
        .packet_count(packet_count), .data_errors(data_errors),
        .sequence_errors(sequence_errors), .crc_errors(crc_errors), .locked(locked));

    integer guard = 0;
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        enable = 1'b1;
        while (packet_count < 32 && guard < 2000) begin
            @(posedge clk);
            guard = guard + 1;
        end
        enable = 1'b0;
        #1;
        if (packet_count < 32 || !locked || data_errors != 0 || sequence_errors != 0 || crc_errors != 0)
            $display("FAIL: M1B PRBS packets=%0d data_err=%0d seq_err=%0d crc_err=%0d", packet_count, data_errors, sequence_errors, crc_errors);
        else
            $display("PASS: M1B source-sync logical PRBS/sequence/CRC packets=%0d words=%0d", packet_count, word_count);
        $finish;
    end
endmodule
