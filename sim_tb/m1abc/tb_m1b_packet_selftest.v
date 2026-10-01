`timescale 1ns/1ps
module tb_m1b_packet_selftest;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire done, pass, fail;
    wire [15:0] good_packets;
    always #10 clk = ~clk;
    m1b_packet_selftest #(.TEST_PACKETS(16), .PAYLOAD_WORDS(4), .TIMEOUT_CYCLES(10000)) dut (
        .clk(clk), .rst_n(rst_n), .done(done), .pass(pass), .fail(fail), .good_packets(good_packets));
    integer guard = 0;
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        while (!done && guard < 12000) begin @(posedge clk); guard = guard + 1; end
        if (done && pass && !fail && good_packets == 16)
            $display("PASS: M1B packet contract PRBS/sequence/CRC good_packets=%0d", good_packets);
        else
            $fatal(1, "FAIL: M1B packet selftest done=%0d pass=%0d fail=%0d good=%0d", done, pass, fail, good_packets);
        $finish;
    end
endmodule
