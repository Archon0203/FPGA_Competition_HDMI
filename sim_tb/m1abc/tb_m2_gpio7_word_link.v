`timescale 1ns/1ps
module tb_m2_gpio7_word_link;
    reg tx_clk=0, rx_clk=0, rst_n=0;
    reg in_valid=0, in_last=0;
    reg [31:0] in_data=0;
    wire in_ready, link_clk, out_valid, out_last, overflow_sticky;
    wire [6:0] link_data;
    wire [31:0] out_data;
    reg out_ready=0;
    integer sent=0, got=0, errors=0, cycles=0;
    always #10 tx_clk=~tx_clk;
    always #7 rx_clk=~rx_clk;

    m2_gpio7_word_tx tx (
        .clk(tx_clk), .rst_n(rst_n), .in_valid(in_valid),
        .in_data(in_data), .in_last(in_last), .in_ready(in_ready),
        .link_data(link_data), .link_clk(link_clk));
    m2_gpio7_word_rx rx (
        .link_clk(link_clk), .link_data(link_data), .link_rst_n(rst_n),
        .sys_clk(rx_clk), .sys_rst_n(rst_n), .out_valid(out_valid),
        .out_data(out_data), .out_last(out_last), .out_ready(out_ready),
        .overflow_sticky(overflow_sticky));

    function [31:0] sample;
        input integer index;
        begin sample = 32'h9e3779b9 ^ (index * 32'h01020305); end
    endfunction

    always @(posedge rx_clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            out_ready <= cycles[3:0] != 4'd0;
            if (out_valid && out_ready) begin
                if (out_data !== sample(got) || out_last !== (got % 13 == 12)) begin
                    $display("mismatch index=%0d data=%h last=%b",got,out_data,out_last);
                    errors <= errors + 1;
                end
                got <= got + 1;
            end
        end
    end

    initial begin
        repeat (5) @(negedge tx_clk);
        rst_n=1;
        for (sent=0;sent<1000;sent=sent+1) begin
            @(negedge tx_clk);
            while (!in_ready) @(negedge tx_clk);
            in_data=sample(sent);
            in_last=(sent % 13 == 12);
            in_valid=1;
            @(negedge tx_clk);
            in_valid=0;
        end
        wait (got == 1000);
        repeat (5) @(posedge rx_clk);
        if (errors || overflow_sticky) $fatal(1,"GPIO7 link errors=%0d overflow=%b",errors,overflow_sticky);
        $display("PASS tb_m2_gpio7_word_link: %0d words, last markers checked",got);
        $finish;
    end
    initial begin #1000000; $fatal(1,"GPIO7 link timeout got=%0d",got); end
endmodule
